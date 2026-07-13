import XCTest
@testable import Ohayo

final class AuthenticationCheckerTests: XCTestCase {
    private func makeScript(_ body: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-auth-(UUID().uuidString).sh")
        try! ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testClaudeLoggedInFalseEmStdoutIdentificaLogout() async {
        let binary = makeScript("printf '{\"loggedIn\":false}\\n'; exit 1")
        let checker = CLIAuthenticationChecker(binaryLocator: { _ in binary })

        let result = await checker.status(for: .claude,
                                          configDir: URL(fileURLWithPath: "/tmp/claude-test"))

        XCTAssertEqual(result, .unauthenticated(log: "{\"loggedIn\":false}"))
    }

    func testClaudeLoggedInTrueAutoriza() async {
        let binary = makeScript("printf '{\"loggedIn\":true}\\n'; exit 0")
        let checker = CLIAuthenticationChecker(binaryLocator: { _ in binary })

        let result = await checker.status(for: .claude,
                                          configDir: URL(fileURLWithPath: "/tmp/claude-test"))

        XCTAssertEqual(result, .authenticated)
    }

    func testCodexMensagemNotLoggedInIdentificaLogout() async {
        let binary = makeScript("echo 'Not logged in' >&2; exit 1")
        let checker = CLIAuthenticationChecker(binaryLocator: { _ in binary })

        let result = await checker.status(for: .codex,
                                          configDir: URL(fileURLWithPath: "/tmp/codex-test"))

        XCTAssertEqual(result, .unauthenticated(log: "Not logged in"))
    }

    func testSaidaDesconhecidaNaoBloqueia() async {
        let binary = makeScript("echo 'unsupported command' >&2; exit 2")
        let checker = CLIAuthenticationChecker(binaryLocator: { _ in binary })

        let result = await checker.status(for: .claude,
                                          configDir: URL(fileURLWithPath: "/tmp/claude-test"))

        XCTAssertEqual(result, .unknown)
    }

    func testCheckerFixaDiretorioDaContaNoAmbiente() async throws {
        let envFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("auth-env-\(UUID().uuidString).txt")
        let binary = makeScript("printf '%s' \"$CODEX_HOME\" > '\(envFile.path)'; exit 0")
        let conta = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-account-\(UUID().uuidString)")
        let checker = CLIAuthenticationChecker(binaryLocator: { _ in binary })

        _ = await checker.status(for: .codex, configDir: conta)

        XCTAssertEqual(try String(contentsOf: envFile, encoding: .utf8), conta.path)
    }
}
