import XCTest
@testable import Ohayo

final class AccountIdentityTests: XCTestCase {
    func testLeEmailDoOauthAccount() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = #"{"oauthAccount":{"emailAddress":"rafael@brq.com"},"userID":"x"}"#
        try json.write(to: dir.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(AccountIdentity.email(forConfigDir: dir), "rafael@brq.com")
    }

    func testSemOauthAccountRetornaNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"userID":"x"}"#.write(to: dir.appendingPathComponent(".claude.json"),
                                     atomically: true, encoding: .utf8)
        XCTAssertNil(AccountIdentity.email(forConfigDir: dir))
    }

    func testArquivoAusenteRetornaNil() {
        let dir = URL(fileURLWithPath: "/tmp/nao-existe-\(UUID().uuidString)")
        XCTAssertNil(AccountIdentity.email(forConfigDir: dir))
    }

    func testEmailDeContaCodexViaJWT() throws {
        // JWT de fixture: header/payload base64url sem assinatura válida —
        // o parser só decodifica o payload, não valida.
        // payload = {"email":"dev@exemplo.com"}
        let payload = Data(#"{"email":"dev@exemplo.com"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let jwt = "eyJhbGciOiJIUzI1NiJ9.\(payload).assinatura"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(".codex-teste-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let auth = #"{"tokens":{"id_token":"\#(jwt)"}}"#
        try auth.write(to: dir.appendingPathComponent("auth.json"),
                       atomically: true, encoding: .utf8)

        XCTAssertEqual(AccountIdentity.email(forConfigDir: dir), "dev@exemplo.com")
    }

    func testAuthJsonIlegivelRetornaNil() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(".codex-teste-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "não é json".write(to: dir.appendingPathComponent("auth.json"),
                               atomically: true, encoding: .utf8)
        XCTAssertNil(AccountIdentity.email(forConfigDir: dir))
    }
}
