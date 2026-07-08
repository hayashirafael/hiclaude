import XCTest
@testable import HiClaude

final class ClaudeRunnerTests: XCTestCase {
    /// Cria um script executável que simula o binário `claude`.
    func makeScript(_ body: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-claude-\(UUID().uuidString).sh")
        try! ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Trava o comando enviado ao CLI: ping mínimo em tokens
    /// (Haiku + effort low + safe-mode + prompt "1+1"). O fake script grava
    /// "$@" e a asserção confere os argumentos exatos, na ordem.
    func testEnviaComandoMinimoDeTokens() async throws {
        let argsFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-args-\(UUID().uuidString).txt")
        let runner = ClaudeRunner(
            timeout: 5,
            binaryOverride: makeScript("printf '%s\\n' \"$@\" > '\(argsFile.path)'; exit 0")
        )

        let result = await runner.run(Message(text: "1+1", kind: .claude))
        XCTAssertEqual(result, .success(()))

        let captured = try String(contentsOf: argsFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
            .map(String.init)
        XCTAssertEqual(captured,
                       ["-p", "--model", "claude-haiku-4-5", "--effort", "low", "--safe-mode", "1+1"])
    }

    func testRepassaPromptCustomComFlagsFixos() async throws {
        let argsFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-args-\(UUID().uuidString).txt")
        let runner = ClaudeRunner(
            timeout: 5,
            binaryOverride: makeScript("printf '%s\\n' \"$@\" > '\(argsFile.path)'; exit 0")
        )

        let result = await runner.run(Message(text: "bom dia", kind: .claude))
        XCTAssertEqual(result, .success(()))

        let captured = try String(contentsOf: argsFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
            .map(String.init)
        XCTAssertEqual(captured,
                       ["-p", "--model", "claude-haiku-4-5", "--effort", "low", "--safe-mode", "bom dia"])
    }

    /// Config por mensagem: modelo/effort escolhidos entram nos args e
    /// `--safe-mode` é omitido quando `safeMode == false`.
    func testArgsRefletemConfigDaMensagem() async throws {
        let argsFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-args-\(UUID().uuidString).txt")
        let runner = ClaudeRunner(
            timeout: 5,
            binaryOverride: makeScript("printf '%s\\n' \"$@\" > '\(argsFile.path)'; exit 0")
        )
        let msg = Message(text: "tarefa", kind: .claude, model: .opus, effort: .high, safeMode: false)
        let result = await runner.run(msg)
        XCTAssertEqual(result, .success(()))

        let captured = try String(contentsOf: argsFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
            .map(String.init)
        XCTAssertEqual(captured,
                       ["-p", "--model", "claude-opus-4-8", "--effort", "high", "tarefa"])
    }

    /// Diretório de trabalho por mensagem: o subprocesso roda no diretório dado.
    func testWorkingDirDaMensagem() async throws {
        let pwdFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("pwd-\(UUID().uuidString).txt")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let runner = ClaudeRunner(
            timeout: 5,
            binaryOverride: makeScript("pwd -P > '\(pwdFile.path)'; exit 0")
        )
        let msg = Message(text: "1+1", kind: .claude, workingDir: dir.path)
        let result = await runner.run(msg)
        XCTAssertEqual(result, .success(()))
        let captured = try String(contentsOf: pwdFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(URL(fileURLWithPath: captured).standardizedFileURL,
                       dir.standardizedFileURL)
    }

    /// Override de conta por mensagem tem prioridade sobre a conta injetada.
    func testConfigDirDaMensagemSobrescreveInjetada() async throws {
        let envFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString).txt")
        let global = FileManager.default.temporaryDirectory
            .appendingPathComponent("global-\(UUID().uuidString)")
        let daMensagem = FileManager.default.temporaryDirectory
            .appendingPathComponent("msg-\(UUID().uuidString)")
        let runner = ClaudeRunner(
            timeout: 5,
            binaryOverride: makeScript("printf '%s' \"$CLAUDE_CONFIG_DIR\" > '\(envFile.path)'; exit 0"),
            configDir: global
        )
        let msg = Message(text: "1+1", kind: .claude, configDir: daMensagem.path)
        let result = await runner.run(msg)
        XCTAssertEqual(result, .success(()))
        let captured = try String(contentsOf: envFile, encoding: .utf8)
        XCTAssertEqual(captured, daMensagem.path)
    }

    /// Modo comando cru: sem prefixo do Claude, roda via shell de login
    /// (`-l -c <texto>`) e o executável é o shell injetado, não o `claude`.
    func testComandoCruRodaViaShellSemPrefixoClaude() async throws {
        let argsFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("shell-args-\(UUID().uuidString).txt")
        let runner = ClaudeRunner(
            timeout: 5,
            binaryOverride: makeScript("echo NAO-DEVE-CHAMAR-CLAUDE >&2; exit 42"),
            shellOverride: makeScript("printf '%s\\n' \"$@\" > '\(argsFile.path)'; exit 0")
        )

        let result = await runner.run(Message(text: "echo oi", kind: .shell))
        XCTAssertEqual(result, .success(()))

        let captured = try String(contentsOf: argsFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }
            .map(String.init)
        XCTAssertEqual(captured, ["-l", "-c", "echo oi"])
    }

    /// O ping deve mirar a conta escolhida via `CLAUDE_CONFIG_DIR`. O fake
    /// script grava o valor visto no ambiente do filho.
    func testFixaClaudeConfigDirDaConta() async throws {
        let envFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString).txt")
        let conta = FileManager.default.temporaryDirectory
            .appendingPathComponent("conta-\(UUID().uuidString)")
        let runner = ClaudeRunner(
            timeout: 5,
            binaryOverride: makeScript("printf '%s' \"$CLAUDE_CONFIG_DIR\" > '\(envFile.path)'; exit 0"),
            configDir: conta
        )
        let result = await runner.run(Message(text: "1+1", kind: .claude))
        XCTAssertEqual(result, .success(()))
        let captured = try String(contentsOf: envFile, encoding: .utf8)
        XCTAssertEqual(captured, conta.path)
    }

    /// Regressao (bug do "hi na conta errada"): sem conta escolhida, o ping
    /// deve fixar em ~/.claude — sobrescrevendo qualquer CLAUDE_CONFIG_DIR
    /// herdado do shell que lancou o app (ex.: uma conta secundaria).
    func testSobrescreveConfigDirHerdadoParaODefault() async throws {
        setenv("CLAUDE_CONFIG_DIR", "/tmp/conta-vazada-do-shell", 1)
        defer { unsetenv("CLAUDE_CONFIG_DIR") }
        let envFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString).txt")
        let runner = ClaudeRunner( // configDir nil -> default
            timeout: 5,
            binaryOverride: makeScript("printf '%s' \"$CLAUDE_CONFIG_DIR\" > '\(envFile.path)'; exit 0")
        )
        let result = await runner.run(Message(text: "1+1", kind: .claude))
        XCTAssertEqual(result, .success(()))
        let captured = try String(contentsOf: envFile, encoding: .utf8)
        XCTAssertEqual(captured, NSHomeDirectory() + "/.claude")
    }

    func testSucessoQuandoExitZero() async {
        let runner = ClaudeRunner(timeout: 5, binaryOverride: makeScript("exit 0"))
        let result = await runner.run(Message(text: "1+1", kind: .claude))
        XCTAssertEqual(result, .success(()))
    }

    func testFalhaCapturaStderr() async {
        let runner = ClaudeRunner(timeout: 5, binaryOverride: makeScript("echo boom >&2; exit 1"))
        let result = await runner.run(Message(text: "1+1", kind: .claude))
        XCTAssertEqual(result, .failure(.failed("boom")))
    }

    func testTimeoutMataOProcesso() async {
        let runner = ClaudeRunner(timeout: 1, binaryOverride: makeScript("sleep 10"))
        let result = await runner.run(Message(text: "1+1", kind: .claude))
        XCTAssertEqual(result, .failure(.timeout))
    }

    /// Regressao: se o pipe de stdout nao for drenado enquanto o processo
    /// roda, uma saida maior que o buffer do SO (~64KB) trava o write do
    /// filho, o processo nunca termina e sendHi() reporta .timeout
    /// erroneamente. Este script emite bem mais que 64KB antes de sair 0.
    func testNaoTravaComStdoutMaiorQueBufferDoPipe() async {
        let runner = ClaudeRunner(
            timeout: 10,
            binaryOverride: makeScript("head -c 200000 /dev/zero | tr '\\0' 'x'; exit 0")
        )
        let result = await runner.run(Message(text: "1+1", kind: .claude))
        XCTAssertEqual(result, .success(()))
    }

    /// Regressao (re-review #1): o readabilityHandler e assincrono/level-
    /// triggered; ao zerar o handler assim que o processo termina, o ultimo
    /// chunk de stderr (escrito logo antes do exit) pode nao ter sido
    /// despachado ainda e se perder, virando "exit N" em vez da mensagem
    /// real. O drain final sincrono garante a captura completa.
    func testCapturaStderrEscritoImediatamenteAntesDoExit() async {
        let runner = ClaudeRunner(
            timeout: 5,
            binaryOverride: makeScript("printf 'erro fatal na cli\\n' >&2; exit 3")
        )
        let result = await runner.run(Message(text: "1+1", kind: .claude))
        XCTAssertEqual(result, .failure(.failed("erro fatal na cli")))
    }

    /// Regressao (re-review #1): stderr grande (acima do buffer do pipe)
    /// deve ser capturado por completo, sem truncar. Usamos uma linha
    /// reconhecivel no fim para provar que a cauda chegou.
    func testCapturaStderrGrandeCompleto() async {
        let runner = ClaudeRunner(
            timeout: 10,
            binaryOverride: makeScript(
                "head -c 200000 /dev/zero | tr '\\0' 'x' >&2; printf 'FIM-DA-STDERR\\n' >&2; exit 1"
            )
        )
        let result = await runner.run(Message(text: "1+1", kind: .claude))
        if case .failure(.failed(let message)) = result {
            XCTAssertTrue(message.hasSuffix("FIM-DA-STDERR"),
                          "stderr truncado; sufixo real: \(String(message.suffix(40)))")
            XCTAssertGreaterThan(message.count, 200000)
        } else {
            XCTFail("esperava .failure(.failed(...)), obtido \(result)")
        }
    }

    /// Regressao (re-review #2): terminate() so manda SIGTERM. Um filho que
    /// ignora SIGTERM faria um waitUntilExit() travar para sempre, e
    /// sendHi() nunca retornaria — o mesmo bug que o fix original matou,
    /// so que na branch de timeout. A espera pos-terminate deve ser
    /// limitada (grace + SIGKILL) e retornar .timeout em tempo limitado.
    func testTimeoutLimitadoMesmoComFilhoQueIgnoraSIGTERM() async {
        let runner = ClaudeRunner(
            timeout: 1,
            binaryOverride: makeScript("trap '' TERM; sleep 30")
        )
        let start = Date()
        let result = await runner.run(Message(text: "1+1", kind: .claude))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result, .failure(.timeout))
        XCTAssertLessThan(elapsed, 10, "sendHi() nao retornou em tempo limitado: \(elapsed)s")
    }
}

extension Result where Success == Void, Failure == RunnerError {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success): return true
        case (.failure(let l), .failure(let r)): return l == r
        default: return false
        }
    }
}

func XCTAssertEqual(_ lhs: Result<Void, RunnerError>, _ rhs: Result<Void, RunnerError>,
                    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(lhs == rhs, "\(lhs) != \(rhs)", file: file, line: line)
}
