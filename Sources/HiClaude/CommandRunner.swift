import Foundation

enum RunnerError: Error, Equatable {
    case cliNotFound(Provider)
    case timeout
    case failed(String)

    func userMessage(language: AppLanguage) -> String {
        let strings = L10n(language: language)
        switch self {
        case .cliNotFound(let provider):
            return strings.cliNotFound(provider)
        case .timeout: return strings.commandTimeout
        case .failed(let message): return message
        }
    }
}

protocol CommandRunning {
    func run(_ message: Message) async -> Result<String, RunnerError>
}

/// Acumula os bytes de stderr recebidos via `readabilityHandler`, que roda
/// em uma dispatch queue de fundo — precisa de lock porque `trimmedString()`
/// (chamado pela task async) e `append()` (chamado pela queue de fundo da
/// readability e pelo drain final síncrono) tocam o mesmo `Data`
/// concorrentemente.
final class PipeBuffer: @unchecked Sendable {
    /// Cap de segurança — o histórico trunca bem antes disso; evita reter
    /// respostas gigantes na memória.
    static let maxBytes = 256 * 1024
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        if data.count < Self.maxBytes {
            data.append(chunk.prefix(Self.maxBytes - data.count))
        }
        lock.unlock()
    }

    func trimmedString() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return Self.validUTF8String(from: snapshot)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `append` corta no `maxBytes` sem olhar para fronteiras de caractere,
    /// então o corte pode cair no meio de uma sequência UTF-8 multibyte
    /// (acentos, emojis). Nesse caso `String(data:encoding:.utf8)` falha
    /// para o `Data` inteiro. Em vez de perder tudo, recua byte a byte (no
    /// máximo 3, o tamanho da maior sequência UTF-8 incompleta possível) até
    /// achar um prefixo válido.
    private static func validUTF8String(from data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        let minLength = max(0, data.count - 3)
        var length = data.count
        while length > minLength {
            length -= 1
            if let string = String(data: data.prefix(length), encoding: .utf8) {
                return string
            }
        }
        return ""
    }
}

struct CommandRunner: CommandRunning {
    var timeout: TimeInterval = 60
    var binaryOverride: URL? // testes
    var shellOverride: URL? // testes
    /// Conta a mirar. Fixado no env do provider (`CLAUDE_CONFIG_DIR`/
    /// `CODEX_HOME`) do subprocesso para não herdar silenciosamente o valor
    /// do shell que lançou o app — senão o ping abre a janela de 5h numa
    /// conta diferente da que o usuário observa.
    var configDir: URL?

    /// Caminhos comuns de instalação; fallback via shell de login cobre
    /// nvm/asdf e instalações exóticas (importante para open source).
    static func candidatePaths(for provider: Provider) -> [String] {
        switch provider {
        case .claude:
            return ["~/.local/bin/claude", "~/.claude/local/claude",
                    "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        case .codex:
            return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "~/.local/bin/codex"]
        }
    }

    static func locate(_ provider: Provider) -> URL? {
        let fm = FileManager.default
        for path in candidatePaths(for: provider) {
            let expanded = NSString(string: path).expandingTildeInPath
            if fm.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v \(provider.cliName)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let path = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    func run(_ message: Message) async -> Result<String, RunnerError> {
        let process = Process()
        switch message.kind {
        case .claude:
            guard let binary = binaryOverride ?? Self.locate(.claude) else {
                return .failure(.cliNotFound(.claude))
            }
            process.executableURL = binary
            // Args montados a partir da config da mensagem (defaults: Haiku,
            // effort low, --safe-mode — o ping mínimo em tokens que só abre a
            // janela de 5h). --safe-mode pula CLAUDE.md/skills/plugins/hooks/MCP;
            // quando desligado, o Claude carrega esse contexto normalmente.
            var args = ["-p",
                        "--model", message.resolvedModel.cliValue,
                        "--effort", message.resolvedEffort.rawValue]
            if message.resolvedSafeMode { args.append("--safe-mode") }
            args.append(message.text)
            process.arguments = args
        case .shell:
            // Comando cru: shell de login para PATH/aliases/pipes/variáveis
            // funcionarem — dá utilidade ao app fora do Claude.
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            process.executableURL = shellOverride ?? URL(fileURLWithPath: shell)
            process.arguments = ["-l", "-c", message.text]
        case .codex:
            guard let binary = binaryOverride ?? Self.locate(.codex) else {
                return .failure(.cliNotFound(.codex))
            }
            process.executableURL = binary
            // Ping mínimo: sandbox read-only e sem exigir repositório git (o
            // diretório default é o home). Modelo/reasoning só entram quando o
            // usuário escolheu — omitir as flags deixa o Codex usar o default da
            // conta (config.toml), o único valor garantidamente aceito pelo
            // plano da conta. Reasoning via -c (TOML) por não haver flag
            // dedicada no codex exec 0.143.0.
            var args = ["exec"]
            if let model = message.codexModel, !model.isEmpty {
                args += ["--model", model]
            }
            args += ["--sandbox", "read-only", "--skip-git-repo-check", "--color", "never"]
            if let reasoning = message.codexReasoning {
                args += ["-c", "model_reasoning_effort=\"\(reasoning.rawValue)\""]
            }
            args.append(message.text)
            process.arguments = args
        }
        let home = NSHomeDirectory()
        // Diretório de trabalho: override da mensagem (se não vazio) senão o home.
        if let wd = message.workingDir, !wd.trimmingCharacters(in: .whitespaces).isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: NSString(string: wd).expandingTildeInPath)
        } else {
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        var env = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin"
        env["PATH"] = [env["PATH"], extraPath].compactMap { $0 }.joined(separator: ":")
        // Sempre fixa a conta alvo no env do provider da mensagem. Prioridade:
        // override da mensagem → conta injetada (só Claude) → default do provider.
        // Definir explicitamente sobrescreve qualquer valor herdado do ambiente.
        let messageConfigDir = (message.configDir?.isEmpty == false)
            ? URL(fileURLWithPath: message.configDir!) : nil
        switch message.kind {
        case .claude, .shell:
            env["CLAUDE_CONFIG_DIR"] = (messageConfigDir ?? configDir
                ?? URL(fileURLWithPath: home).appendingPathComponent(".claude")).path
        case .codex:
            env["CODEX_HOME"] = (messageConfigDir
                ?? URL(fileURLWithPath: home).appendingPathComponent(".codex")).path
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Drena os pipes concorrentemente enquanto o processo roda: se
        // ninguem ler, uma saida maior que o buffer do SO (~64KB) trava o
        // write do filho e o processo nunca termina (deadlock classico de
        // Process/Pipe), fazendo sendHi() reportar .timeout erroneamente.
        let stdoutBuffer = PipeBuffer()
        let stderrBuffer = PipeBuffer()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stdoutBuffer.append(chunk) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                stderrBuffer.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return .failure(.failed(error.localizedDescription))
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        let timedOut = process.isRunning
        if timedOut {
            // `terminate()` só manda SIGTERM; um filho que ignora/trata o
            // sinal faria um `waitUntilExit()` travar para sempre —
            // reintroduzindo o mesmo bug (subprocesso que nunca reporta
            // término) na branch de timeout. Então limitamos a espera: um
            // grace period curto e, se ainda vivo, escalamos para SIGKILL.
            process.terminate()
            let graceDeadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < graceDeadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = nil
        outPipe.fileHandleForReading.readabilityHandler = nil

        if timedOut {
            return .failure(.timeout)
        }
        // O `readabilityHandler` é assíncrono/level-triggered: ao ver o
        // processo já terminado e zerar o handler, o último chunk (ou o
        // evento de EOF) pode não ter sido despachado ao bloco ainda —
        // zerar cancela a DispatchSourceRead e essa cauda se perderia.
        // Depois de cancelar a source, um `readToEnd()` bloqueante no mesmo
        // fd é seguro e recupera a completude do `readToEnd()` pré-fix.
        if let rest = try? outPipe.fileHandleForReading.readToEnd(), !rest.isEmpty {
            stdoutBuffer.append(rest)
        }
        if let rest = try? errPipe.fileHandleForReading.readToEnd(), !rest.isEmpty {
            stderrBuffer.append(rest)
        }
        if process.terminationStatus != 0 {
            let message = stderrBuffer.trimmedString()
            return .failure(.failed(message.isEmpty ? "exit \(process.terminationStatus)" : message))
        }
        return .success(stdoutBuffer.trimmedString())
    }
}
