import XCTest
@testable import HiClaude

final class MockDetector: SessionDetecting {
    var end: Date?
    func activeWindowEnd() async -> Date? { end }
}

final class MockRunner: ClaudeRunning {
    var result: Result<Void, RunnerError> = .success(())
    var calls = 0
    var lastPrompt: String?
    func sendHi(prompt: String) async -> Result<Void, RunnerError> {
        calls += 1
        lastPrompt = prompt
        return result
    }
}

final class MockNotifier: FailureNotifying {
    var messages: [String] = []
    func notifyFailure(message: String) { messages.append(message) }
}

@MainActor
final class FireControllerTests: XCTestCase {
    var state: AppState!
    var detector: MockDetector!
    var runner: MockRunner!
    var notifier: MockNotifier!
    var controller: FireController!
    let now = Date(timeIntervalSince1970: 1_783_000_000)

    override func setUp() async throws {
        state = AppState(defaults: UserDefaults(suiteName: "hiclaude-test-\(UUID().uuidString)")!)
        detector = MockDetector()
        runner = MockRunner()
        notifier = MockNotifier()
        controller = FireController(state: state, detector: detector, runner: runner,
                                    notifier: notifier, clock: FakeClock(now: now))
    }

    func testJanelaAtivaPulaSemExecutar() async {
        let end = now.addingTimeInterval(3600)
        detector.end = end
        await controller.fire(manual: false)
        XCTAssertEqual(runner.calls, 0)
        XCTAssertEqual(state.lastEvent, FireEvent(date: now, result: .skipped(activeUntil: end)))
        XCTAssertEqual(state.activeWindowEnd, end)
    }

    func testSucessoRegistraEvento() async {
        await controller.fire(manual: false)
        XCTAssertEqual(runner.calls, 1)
        XCTAssertEqual(state.lastEvent, FireEvent(date: now, result: .success))
        XCTAssertTrue(notifier.messages.isEmpty)
    }

    func testFalhaAgendadaNotifica() async {
        runner.result = .failure(.failed("sem rede"))
        await controller.fire(manual: false)
        XCTAssertEqual(state.lastEvent, FireEvent(date: now, result: .failure(message: "sem rede")))
        XCTAssertEqual(notifier.messages, ["sem rede"])
    }

    func testFalhaManualNaoNotifica() async {
        runner.result = .failure(.failed("sem rede"))
        await controller.fire(manual: true)
        XCTAssertTrue(notifier.messages.isEmpty)
    }

    func testCliNaoEncontradoMarcaClaudeFound() async {
        runner.result = .failure(.cliNotFound)
        await controller.fire(manual: false)
        XCTAssertFalse(state.claudeFound)
    }

    func testEnviaMensagemPadraoPorDefault() async {
        await controller.fire(manual: false)
        XCTAssertEqual(runner.lastPrompt, "1+1")
    }

    func testEnviaMensagemAtivaEscolhida() async {
        state.addFavorite("bom dia")
        state.setActiveMessage("bom dia")
        await controller.fire(manual: false)
        XCTAssertEqual(runner.lastPrompt, "bom dia")
    }
}
