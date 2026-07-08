import XCTest
@testable import HiClaude

final class MockDetector: SessionDetecting {
    var end: Date?
    var lastProjectsDir: URL?
    func activeWindowEnd(projectsDir: URL) async -> Date? {
        lastProjectsDir = projectsDir
        return end
    }
}

final class MockRunner: ClaudeRunning {
    var result: Result<Void, RunnerError> = .success(())
    var calls = 0
    var lastMessage: Message?
    func run(_ message: Message) async -> Result<Void, RunnerError> {
        calls += 1
        lastMessage = message
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
        XCTAssertEqual(runner.lastMessage, AppState.defaultMessage)
    }

    func testEnviaMensagemAtivaEscolhida() async {
        let msg = Message(text: "bom dia", kind: .claude)
        state.addFavorite(text: "bom dia", kind: .claude)
        state.setActiveMessage(msg)
        await controller.fire(manual: false)
        XCTAssertEqual(runner.lastMessage, msg)
    }

    /// A janela é checada na conta efetiva da mensagem (conta por mensagem):
    /// o detector recebe o `projects` do override, não o da conta global.
    func testJanelaChecadaNaContaDaMensagem() async throws {
        let conta = FileManager.default.temporaryDirectory
            .appendingPathComponent("conta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: conta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: conta) }
        let msg = Message(text: "oi", kind: .claude, configDir: conta.path)
        state.addFavorite(text: "oi", kind: .claude, configDir: conta.path)
        state.setActiveMessage(msg)
        await controller.fire(manual: false)
        XCTAssertEqual(detector.lastProjectsDir?.standardizedFileURL,
                       conta.appendingPathComponent("projects").standardizedFileURL)
    }

    /// Comando cru ignora o skip de janela ativa e sempre executa.
    func testComandoCruRodaMesmoComJanelaAtiva() async {
        detector.end = now.addingTimeInterval(3600)
        let msg = Message(text: "echo oi", kind: .shell)
        state.addFavorite(text: "echo oi", kind: .shell)
        state.setActiveMessage(msg)
        await controller.fire(manual: false)
        XCTAssertEqual(runner.calls, 1)
        XCTAssertEqual(runner.lastMessage, msg)
        XCTAssertEqual(state.lastEvent, FireEvent(date: now, result: .success))
    }
}
