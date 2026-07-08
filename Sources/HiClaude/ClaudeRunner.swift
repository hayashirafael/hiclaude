import Foundation

enum RunnerError: Error, Equatable {
    case cliNotFound
    case timeout
    case failed(String)

    var userMessage: String {
        switch self {
        case .cliNotFound: return "CLI do Claude não encontrado"
        case .timeout: return "claude -p não respondeu em 60s"
        case .failed(let message): return message
        }
    }
}

protocol ClaudeRunning {
    func sendHi() async -> Result<Void, RunnerError>
}

/// Acumula os bytes de stderr recebidos via `readabilityHandler`, que roda
/// em uma dispatch queue de fundo — precisa de lock porque `trimmedString()`
/// (chamado pela task async) e `append()` (chamado pela queue de fundo da
/// readability e pelo drain final síncrono) tocam o mesmo `Data`
/// concorrentemente.
final class StderrBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func trimmedString() -> String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct ClaudeRunner: ClaudeRunning {
    var timeout: TimeInterval = 60
    var binaryOverride: URL? // testes

    /// Caminhos comuns de instalação; fallback via shell de login cobre
    /// nvm/asdf e instalações exóticas (importante para open source).
    static let candidatePaths = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
    ]

    static func locateClaude() -> URL? {
        let fm = FileManager.default
        for path in candidatePaths {
            let expanded = NSString(string: path).expandingTildeInPath
            if fm.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v claude"]
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

    func sendHi() async -> Result<Void, RunnerError> {
        guard let binary = binaryOverride ?? Self.locateClaude() else {
            return .failure(.cliNotFound)
        }
        let process = Process()
        process.executableURL = binary
        // Ping mínimo em tokens: Haiku (modelo mais barato) com esforço baixo,
        // --safe-mode pula CLAUDE.md/skills/plugins/hooks/MCP (corta o contexto
        // de entrada), e "1+1" gera saída de ~1 token. O objetivo é só iniciar
        // a janela de 5h — o conteúdo da resposta é irrelevante.
        process.arguments = [
            "-p",
            "--model", "claude-haiku-4-5",
            "--effort", "low",
            "--safe-mode",
            "1+1",
        ]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin"
        env["PATH"] = [env["PATH"], extraPath].compactMap { $0 }.joined(separator: ":")
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Drena os pipes concorrentemente enquanto o processo roda: se
        // ninguem ler, uma saida maior que o buffer do SO (~64KB) trava o
        // write do filho e o processo nunca termina (deadlock classico de
        // Process/Pipe), fazendo sendHi() reportar .timeout erroneamente.
        let stderrBuffer = StderrBuffer()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData // descarta stdout, so precisamos drenar
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
        if let rest = try? errPipe.fileHandleForReading.readToEnd(), !rest.isEmpty {
            stderrBuffer.append(rest)
        }
        if process.terminationStatus != 0 {
            let message = stderrBuffer.trimmedString()
            return .failure(.failed(message.isEmpty ? "exit \(process.terminationStatus)" : message))
        }
        return .success(())
    }
}
