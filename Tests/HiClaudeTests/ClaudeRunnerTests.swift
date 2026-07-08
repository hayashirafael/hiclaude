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

    func testSucessoQuandoExitZero() async {
        let runner = ClaudeRunner(timeout: 5, binaryOverride: makeScript("exit 0"))
        let result = await runner.sendHi()
        XCTAssertEqual(result, .success(()))
    }

    func testFalhaCapturaStderr() async {
        let runner = ClaudeRunner(timeout: 5, binaryOverride: makeScript("echo boom >&2; exit 1"))
        let result = await runner.sendHi()
        XCTAssertEqual(result, .failure(.failed("boom")))
    }

    func testTimeoutMataOProcesso() async {
        let runner = ClaudeRunner(timeout: 1, binaryOverride: makeScript("sleep 10"))
        let result = await runner.sendHi()
        XCTAssertEqual(result, .failure(.timeout))
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
