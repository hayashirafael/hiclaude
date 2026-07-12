import XCTest
@testable import Ohayo

final class AppVersionTests: XCTestCase {
    func testBundleVersionHasPrecedence() throws {
        let infoURL = try makeInfoPlist(version: "0.3.0")

        XCTAssertEqual(
            AppVersion.resolve(bundleVersion: "1.2.3", developmentInfoPlistURL: infoURL),
            "1.2.3")
    }

    func testFallsBackToDevelopmentInfoPlist() throws {
        let infoURL = try makeInfoPlist(version: "0.3.0")

        XCTAssertEqual(
            AppVersion.resolve(bundleVersion: nil, developmentInfoPlistURL: infoURL),
            "0.3.0")
    }

    func testFallsBackToDashWhenNoVersionSourceExists() {
        XCTAssertEqual(AppVersion.resolve(bundleVersion: nil, developmentInfoPlistURL: nil), "-")
    }

    private func makeInfoPlist(version: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": version],
            format: .xml,
            options: 0)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
