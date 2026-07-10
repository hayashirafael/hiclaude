import XCTest
@testable import HiClaude

final class TerminalLauncherTests: XCTestCase {
    func testClaudeInterativoNaoUsaPrintEMontaAmbiente() throws {
        let binary = URL(fileURLWithPath: "/tmp/fake claude")
        let msg = Message(text: "bom dia 'hoje'", kind: .claude,
                          model: .opus, effort: .high, safeMode: false,
                          configDir: "/tmp/conta claude",
                          workingDir: "/tmp/projeto teste")

        let spec = try XCTUnwrap(TerminalLauncher.spec(for: msg, claudeBinary: binary))

        XCTAssertTrue(spec.terminalScript.contains("export CLAUDE_CONFIG_DIR='/tmp/conta claude'"))
        XCTAssertTrue(spec.terminalScript.contains("cd '/tmp/projeto teste'"))
        XCTAssertTrue(spec.terminalScript.contains("'/tmp/fake claude'"))
        XCTAssertTrue(spec.terminalScript.contains("'--model' 'claude-opus-4-8'"))
        XCTAssertTrue(spec.terminalScript.contains("'--effort' 'high'"))
        XCTAssertTrue(spec.terminalScript.contains("'bom dia '\\''hoje'\\'''"))
        XCTAssertFalse(spec.terminalScript.contains(" '-p' "))
        // O login shell do Terminal já tem o PATH do usuário e o binário é
        // invocado por caminho absoluto — exportar o PATH herdado do app
        // (gigante/duplicado) truncava o comando no Terminal.
        XCTAssertFalse(spec.terminalScript.contains("export PATH"))
    }

    func testLaunchEscreveScriptEmArquivoTemporarioERodaViaSh() async throws {
        let captured = Captura()
        var launcher = TerminalLauncher(claudeBinaryOverride: URL(fileURLWithPath: "/tmp/fake claude"))
        launcher.appleScriptRunner = { script in
            captured.script = script
            return .success(())
        }
        let msg = Message(text: "bom dia", kind: .claude,
                          configDir: "/tmp/conta claude", workingDir: "/tmp/proj")

        guard case .success = await launcher.launch(msg) else {
            return XCTFail("launch deveria ter sucesso")
        }

        let script = try XCTUnwrap(captured.script)
        // O do script roda o arquivo, não o comando inteiro embutido (imune a
        // truncamento com prompts longos).
        XCTAssertTrue(script.contains(#"do script "/bin/sh '"#))
        let regex = try NSRegularExpression(pattern: #"/bin/sh '([^']+)'"#)
        let range = NSRange(script.startIndex..., in: script)
        let match = try XCTUnwrap(regex.firstMatch(in: script, range: range))
        let path = String(script[Range(match.range(at: 1), in: script)!])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(content.contains("export CLAUDE_CONFIG_DIR='/tmp/conta claude'"))
        XCTAssertTrue(content.contains("cd '/tmp/proj'"))
        XCTAssertTrue(content.contains("'/tmp/fake claude'"))
        XCTAssertTrue(content.contains("rm -f -- '\(path)'")) // autolimpeza ao terminar
    }

    func testSpecUsaWorkspaceDoAppComoDiretorioPadrao() throws {
        // O default NÃO pode ser o home: o Claude Code nunca persiste o trust
        // do home (só por sessão), então abrir lá pede confirmação toda vez.
        let msg = Message(text: "oi", kind: .claude) // sem workingDir
        let spec = try XCTUnwrap(TerminalLauncher.spec(
            for: msg, claudeBinary: URL(fileURLWithPath: "/tmp/claude")))
        let workspace = NSHomeDirectory() + "/Library/Application Support/HiClaude/workspace"
        XCTAssertTrue(spec.terminalScript.contains("cd '\(workspace)'"))
    }

    func testLaunchPreConfiaPastaDeTrabalhoNoClaudeJsonDaConta() async throws {
        let conta = try makeTempDir()
        let proj = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: conta); try? FileManager.default.removeItem(at: proj) }
        // .claude.json existente com outras chaves que DEVEM ser preservadas.
        let existente: [String: Any] = [
            "oauthAccount": ["emailAddress": "x@y.z"],
            "projects": ["/outra": ["hasTrustDialogAccepted": false, "allowedTools": ["Bash"]]]
        ]
        let jsonURL = conta.appendingPathComponent(".claude.json")
        try JSONSerialization.data(withJSONObject: existente).write(to: jsonURL)

        var launcher = TerminalLauncher(claudeBinaryOverride: URL(fileURLWithPath: "/tmp/claude"))
        launcher.appleScriptRunner = { _ in .success(()) }
        let msg = Message(text: "oi", kind: .claude,
                          configDir: conta.path, workingDir: proj.path)
        guard case .success = await launcher.launch(msg) else { return XCTFail() }

        let atualizado = try JSONSerialization.jsonObject(
            with: Data(contentsOf: jsonURL)) as! [String: Any]
        let projects = atualizado["projects"] as! [String: Any]
        let entrada = projects[proj.path] as! [String: Any]
        XCTAssertEqual(entrada["hasTrustDialogAccepted"] as? Bool, true)
        XCTAssertEqual(entrada["hasClaudeMdExternalIncludesApproved"] as? Bool, true)
        XCTAssertEqual(entrada["hasClaudeMdExternalIncludesWarningShown"] as? Bool, true)
        // Preserva o resto do arquivo e das entradas existentes.
        XCTAssertNotNil(atualizado["oauthAccount"])
        let outra = projects["/outra"] as! [String: Any]
        XCTAssertEqual(outra["allowedTools"] as? [String], ["Bash"])
    }

    func testLaunchCriaClaudeJsonQuandoAusente() async throws {
        let conta = try makeTempDir()
        let proj = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: conta); try? FileManager.default.removeItem(at: proj) }
        var launcher = TerminalLauncher(claudeBinaryOverride: URL(fileURLWithPath: "/tmp/claude"))
        launcher.appleScriptRunner = { _ in .success(()) }
        let msg = Message(text: "oi", kind: .claude,
                          configDir: conta.path, workingDir: proj.path)
        guard case .success = await launcher.launch(msg) else { return XCTFail() }

        let json = try JSONSerialization.jsonObject(with: Data(
            contentsOf: conta.appendingPathComponent(".claude.json"))) as! [String: Any]
        let entrada = (json["projects"] as! [String: Any])[proj.path] as! [String: Any]
        XCTAssertEqual(entrada["hasTrustDialogAccepted"] as? Bool, true)
        XCTAssertEqual(entrada["hasClaudeMdExternalIncludesApproved"] as? Bool, true)
        XCTAssertEqual(entrada["hasClaudeMdExternalIncludesWarningShown"] as? Bool, true)
    }

    func testLaunchAprovaImportsExternosMesmoComTrustJaAceito() async throws {
        // Regressão do prompt "Allow external CLAUDE.md file imports?": conta já
        // confiada (hasTrustDialogAccepted=true) mas que nunca aprovou imports
        // externos. O early-return antigo (só olhava o trust) pulava a
        // aprovação, e a sessão travava esperando Enter.
        let conta = try makeTempDir()
        let proj = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: conta); try? FileManager.default.removeItem(at: proj) }
        let existente: [String: Any] = [
            "projects": [proj.path: ["hasTrustDialogAccepted": true]]
        ]
        let jsonURL = conta.appendingPathComponent(".claude.json")
        try JSONSerialization.data(withJSONObject: existente).write(to: jsonURL)

        var launcher = TerminalLauncher(claudeBinaryOverride: URL(fileURLWithPath: "/tmp/claude"))
        launcher.appleScriptRunner = { _ in .success(()) }
        let msg = Message(text: "oi", kind: .claude,
                          configDir: conta.path, workingDir: proj.path)
        guard case .success = await launcher.launch(msg) else { return XCTFail() }

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as! [String: Any]
        let entrada = (json["projects"] as! [String: Any])[proj.path] as! [String: Any]
        XCTAssertEqual(entrada["hasTrustDialogAccepted"] as? Bool, true)
        XCTAssertEqual(entrada["hasClaudeMdExternalIncludesApproved"] as? Bool, true)
        XCTAssertEqual(entrada["hasClaudeMdExternalIncludesWarningShown"] as? Bool, true)
    }

    func testLaunchCodexNaoMexeEmClaudeJson() async throws {
        let conta = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: conta) }
        var launcher = TerminalLauncher(codexBinaryOverride: URL(fileURLWithPath: "/tmp/codex"))
        launcher.appleScriptRunner = { _ in .success(()) }
        let msg = Message(text: "oi", kind: .codex, configDir: conta.path, workingDir: conta.path)
        guard case .success = await launcher.launch(msg) else { return XCTFail() }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: conta.appendingPathComponent(".claude.json").path))
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hiclaude-term-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Caixa de captura para o runner fake (struct não deixa mutar var local
    /// de fora do closure de forma limpa).
    private final class Captura { var script: String? }

    func testCodexInterativoNaoUsaExecEMontaReasoning() throws {
        let binary = URL(fileURLWithPath: "/tmp/fake-codex")
        var msg = Message(text: "revise isso", kind: .codex,
                          configDir: "/tmp/conta-codex",
                          workingDir: "/tmp/proj")
        msg.codexModel = "gpt-5.5"
        msg.codexReasoning = .high

        let spec = try XCTUnwrap(TerminalLauncher.spec(for: msg, codexBinary: binary))

        XCTAssertTrue(spec.terminalScript.contains("export CODEX_HOME='/tmp/conta-codex'"))
        XCTAssertTrue(spec.terminalScript.contains("cd '/tmp/proj'"))
        XCTAssertTrue(spec.terminalScript.contains("'/tmp/fake-codex'"))
        XCTAssertTrue(spec.terminalScript.contains("'--model' 'gpt-5.5'"))
        XCTAssertTrue(spec.terminalScript.contains("'--sandbox' 'read-only'"))
        XCTAssertTrue(spec.terminalScript.contains("'-c' 'model_reasoning_effort=\"high\"'"))
        XCTAssertTrue(spec.terminalScript.contains("'revise isso'"))
        XCTAssertFalse(spec.terminalScript.contains("'exec'"))
    }

    func testAppleScriptEscapaComandoParaDoScript() {
        let script = TerminalLauncher.appleScript(forTerminalScript: #"echo "oi"; printf '\\'"#)
        XCTAssertTrue(script.contains(#"do script "echo \"oi\"; printf '\\\\'"#))
    }
}
