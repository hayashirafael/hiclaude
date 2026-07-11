import AppKit
import Foundation

protocol TerminalLaunching {
    func launch(_ message: Message) async -> Result<Void, RunnerError>
}

struct TerminalLaunchSpec: Equatable {
    let terminalScript: String
    /// Pasta da conta usada no env (`CLAUDE_CONFIG_DIR`/`CODEX_HOME`).
    let accountDir: String
    /// Diretório de trabalho resolvido (o do workspace do app quando a
    /// mensagem não define um).
    let workingDir: String
}

struct TerminalLauncher: TerminalLaunching {
    var claudeBinaryOverride: URL?
    var codexBinaryOverride: URL?
    var appleScriptRunner: (String) -> Result<Void, RunnerError> = Self.runAppleScript

    func launch(_ message: Message) async -> Result<Void, RunnerError> {
        guard let spec = Self.spec(
            for: message,
            claudeBinary: claudeBinaryOverride,
            codexBinary: codexBinaryOverride
        ) else {
            return .failure(.cliNotFound(message.kind == .codex ? .codex : .claude))
        }
        // Garante o workspace padrão do app e pré-confia a pasta de trabalho
        // na conta (mecanismo documentado do Claude Code) — sem isso o CLI
        // interativo pede "do you trust this folder?" na primeira sessão.
        // Falha aqui não impede o launch: no pior caso o prompt aparece.
        try? FileManager.default.createDirectory(
            atPath: spec.workingDir, withIntermediateDirectories: true)
        if message.kind == .claude {
            Self.seedTrust(accountDir: spec.accountDir, workingDir: spec.workingDir)
        }
        // O script vai num arquivo temporário em vez de embutido no
        // `do script`: comandos longos (prompt grande, PATH inflado) chegavam
        // truncados no Terminal e nunca executavam. A última linha apaga o
        // próprio arquivo quando a sessão termina.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("hiclaude-terminal-\(UUID().uuidString).sh")
        let content = spec.terminalScript + "\nrm -f -- \(Self.shellQuote(file.path))\n"
        do {
            try content.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.failed("falha ao gravar o script do terminal: \(error.localizedDescription)"))
        }
        let script = Self.appleScript(forTerminalScript: "/bin/sh \(Self.shellQuote(file.path))")
        let result = appleScriptRunner(script)
        if case .failure = result {
            // O `rm` de auto-limpeza é a última linha do próprio script — se o
            // Terminal não abriu, ele nunca roda. Remove aqui para o arquivo
            // temporário não vazar.
            try? FileManager.default.removeItem(at: file)
        }
        return result
    }

    static func spec(for message: Message,
                     claudeBinary: URL? = nil,
                     codexBinary: URL? = nil,
                     defaultWorkspace: URL? = nil) -> TerminalLaunchSpec? {
        let provider: Provider
        let binary: URL?
        var args: [String] = []
        switch message.kind {
        case .claude:
            provider = .claude
            binary = claudeBinary ?? CommandRunner.locate(.claude)
            args = ["--model", message.resolvedModel.cliValue,
                    "--effort", message.resolvedEffort.rawValue]
            if message.resolvedSafeMode { args.append("--safe-mode") }
            args.append(message.text)
        case .codex:
            provider = .codex
            binary = codexBinary ?? CommandRunner.locate(.codex)
            if let model = message.codexModel, !model.isEmpty {
                args += ["--model", model]
            }
            args += ["--sandbox", "read-only"]
            if let reasoning = message.codexReasoning {
                args += ["-c", "model_reasoning_effort=\"\(reasoning.rawValue)\""]
            }
            args.append(message.text)
        case .shell:
            return nil
        }
        guard let binary else { return nil }

        let home = NSHomeDirectory()
        let workingDir: String
        if let wd = message.workingDir, !wd.trimmingCharacters(in: .whitespaces).isEmpty {
            workingDir = NSString(string: wd).expandingTildeInPath
        } else {
            // Nunca o home: o Claude Code não persiste o trust do home (vale
            // só pela sessão), então abrir lá pediria confirmação toda vez.
            workingDir = (defaultWorkspace ?? defaultWorkspaceDir).path
        }

        let messageConfigDir = (message.configDir?.isEmpty == false)
            ? URL(fileURLWithPath: message.configDir!) : nil
        let envKey = provider.envKey
        let envValue: String
        if provider == .codex {
            envValue = (messageConfigDir
                ?? URL(fileURLWithPath: home).appendingPathComponent(".codex")).path
        } else {
            envValue = (messageConfigDir
                ?? URL(fileURLWithPath: home).appendingPathComponent(".claude")).path
        }
        // Sem `export PATH`: o Terminal abre um login shell com o PATH do
        // próprio usuário, e o binário é invocado por caminho absoluto —
        // exportar o PATH herdado do app (gigante quando lançado de um shell
        // poluído) truncava o comando.
        let command = ([binary.path] + args).map(shellQuote).joined(separator: " ")
        let terminalScript = [
            "export \(envKey)=\(shellQuote(envValue))",
            "cd \(shellQuote(workingDir))",
            command
        ].joined(separator: "; ")
        return TerminalLaunchSpec(terminalScript: terminalScript,
                                  accountDir: envValue, workingDir: workingDir)
    }

    /// Pasta neutra do app onde as sessões interativas abrem por padrão.
    static var defaultWorkspaceDir: URL {
        AppPaths.workspaceDirectory()
    }

    /// Pré-aprova, no `.claude.json` da conta, os dois consentimentos que o
    /// disparo não-supervisionado não pode responder à mão, ambos em
    /// `projects["<pasta>"]`:
    /// - `hasTrustDialogAccepted = true` — a confiança da pasta (trust dialog).
    /// - `hasClaudeMdExternalIncludesApproved = true` +
    ///   `hasClaudeMdExternalIncludesWarningShown = true` — o "Yes, allow
    ///   external imports" (quando o CLAUDE.md importa arquivos fora do working
    ///   dir, ex.: `@RTK.md`). Sem isso a sessão `claude` trava esperando Enter.
    /// Não há flag/env do `claude` que responda "sim" a esses imports mantendo o
    /// CLAUDE.md ativo (`--bare`/`--safe-mode` desligariam o CLAUDE.md); semear a
    /// config é a única via. Preserva todo o resto do arquivo; não reescreve
    /// quando as três chaves já estão `true`.
    static func seedTrust(accountDir: String, workingDir: String) {
        let url = URL(fileURLWithPath: accountDir).appendingPathComponent(".claude.json")
        // Canonicaliza a chave: o `claude` grava o trust sob o caminho que o
        // `getcwd` devolve depois do `cd` — símbolos resolvidos (/tmp →
        // /private/tmp), sem barra final nem segmentos `.`/`..`. Semear sob o
        // caminho cru (ex.: /tmp/x) não casaria e a sessão travaria no prompt.
        let workingDir = URL(fileURLWithPath: workingDir).resolvingSymlinksInPath().path
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url) {
            // Arquivo existe: só mexemos se soubermos parseá-lo. Um parse que
            // falha (bytes truncados por escrita concorrente do CLI, JSON
            // corrompido) NÃO pode virar root=[:] e ser regravado por cima —
            // isso apagaria oauthAccount, trust de outros projetos e settings.
            // Sem lugar seguro para semear, abortamos: no pior caso o prompt
            // interativo aparece uma vez.
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            root = parsed
        }
        var projects = root["projects"] as? [String: Any] ?? [:]
        var entry = projects[workingDir] as? [String: Any] ?? [:]
        let trust = entry["hasTrustDialogAccepted"] as? Bool == true
        let approved = entry["hasClaudeMdExternalIncludesApproved"] as? Bool == true
        let warned = entry["hasClaudeMdExternalIncludesWarningShown"] as? Bool == true
        if trust && approved && warned { return } // já tudo semeado
        entry["hasTrustDialogAccepted"] = true
        entry["hasClaudeMdExternalIncludesApproved"] = true
        entry["hasClaudeMdExternalIncludesWarningShown"] = true
        projects[workingDir] = entry
        root["projects"] = projects
        if let data = try? JSONSerialization.data(withJSONObject: root) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func appleScript(forTerminalScript terminalScript: String) -> String {
        """
        tell application "Terminal"
            activate
            do script "\(appleScriptStringLiteral(terminalScript))"
        end tell
        """
    }

    private static func runAppleScript(_ script: String) -> Result<Void, RunnerError> {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return .failure(.failed("failed to create AppleScript"))
        }
        appleScript.executeAndReturnError(&error)
        if let error {
            return .failure(.failed(error.description))
        }
        return .success(())
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
