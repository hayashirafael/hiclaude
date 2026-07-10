import XCTest
@testable import HiClaude

final class AppPathsTests: XCTestCase {
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("hiyashi-paths-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    func testMigraWorkspaceLegadoEPreservaLock() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = AppPaths.legacySupportDirectory(home: home)
        let workspace = legacy.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("ok".utf8).write(to: workspace.appendingPathComponent("marker"))
        try Data().write(to: legacy.appendingPathComponent("instance.lock"))

        AppPaths.migrateSupportDirectory(home: home)

        let migrated = AppPaths.supportDirectory(home: home).appendingPathComponent("workspace")
        XCTAssertTrue(FileManager.default.fileExists(atPath: migrated.appendingPathComponent("marker").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("instance.lock").path))
        XCTAssertEqual(AppPaths.workspaceDirectory(home: home), migrated)
    }

    func testMigracaoNaoSobrescreveDestinoEPermaneceIdempotente() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = AppPaths.legacySupportDirectory(home: home).appendingPathComponent("workspace")
        let current = AppPaths.supportDirectory(home: home).appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("legado".utf8).write(to: legacy.appendingPathComponent("marker"))
        try Data("novo".utf8).write(to: current.appendingPathComponent("marker"))

        AppPaths.migrateSupportDirectory(home: home)
        AppPaths.migrateSupportDirectory(home: home)

        let data = try Data(contentsOf: current.appendingPathComponent("marker"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "novo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("marker").path))
    }

    func testWorkspaceNovoEhDefaultSemLegado() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertEqual(
            AppPaths.workspaceDirectory(home: home),
            AppPaths.supportDirectory(home: home).appendingPathComponent("workspace")
        )
    }
}
