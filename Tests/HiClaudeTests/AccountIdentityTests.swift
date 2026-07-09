import XCTest
@testable import HiClaude

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
}
