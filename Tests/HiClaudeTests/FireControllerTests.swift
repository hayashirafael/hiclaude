import XCTest
@testable import HiClaude

/// Relógio fake para testes determinísticos (compartilhado com RenewalEngineTests).
final class FakeClock: Clock {
    var now: Date
    init(now: Date) { self.now = now }
}

final class MockDetector: SessionDetecting {
    var end: Date?
    var lastAccount: URL?
    func activeWindowEnd(account: URL) async -> Date? {
        lastAccount = account
        return end
    }
}

final class MockRunner: CommandRunning {
    var result: Result<String, RunnerError> = .success("")
    var calls = 0
    var lastMessage: Message?
    func run(_ message: Message) async -> Result<String, RunnerError> {
        calls += 1
        lastMessage = message
        return result
    }
}

final class MockNotifier: Notifying {
    var messages: [String] = []
    var titles: [String] = []
    var responses: [(messageText: String, response: String)] = []
    func notifyFailure(title: String, message: String) {
        titles.append(title)
        messages.append(message)
    }
    func notifyResponse(title: String, response: String) {
        responses.append((title, response))
    }
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
        await controller.fire(message: AppState.defaultMessage, origin: .scheduled)
        XCTAssertEqual(runner.calls, 0)
        XCTAssertEqual(state.lastEvent,
                       FireEvent(date: now, result: .skipped(activeUntil: end),
                                 messageText: "1+1", account: ".claude", origin: .scheduled))
    }

    func testSucessoRegistraEventoNoHistorico() async {
        await controller.fire(message: AppState.defaultMessage, origin: .scheduled)
        XCTAssertEqual(runner.calls, 1)
        XCTAssertEqual(state.lastEvent,
                       FireEvent(date: now, result: .success,
                                 messageText: "1+1", account: ".claude", origin: .scheduled))
        XCTAssertEqual(state.history.count, 1)
        XCTAssertTrue(notifier.messages.isEmpty)
    }

    func testFalhaAgendadaNotifica() async {
        runner.result = .failure(.failed("sem rede"))
        await controller.fire(message: AppState.defaultMessage, origin: .scheduled)
        XCTAssertEqual(state.lastEvent,
                       FireEvent(date: now, result: .failure(message: "sem rede"),
                                 messageText: "1+1", account: ".claude", origin: .scheduled))
        XCTAssertEqual(notifier.titles, ["HiClaude: run failed"])
        XCTAssertEqual(notifier.messages, ["sem rede"])
    }

    func testFalhaManualNaoNotifica() async {
        runner.result = .failure(.failed("sem rede"))
        await controller.fire(message: AppState.defaultMessage, origin: .manual)
        XCTAssertTrue(notifier.messages.isEmpty)
    }

    func testCliNaoEncontradoMarcaCliFound() async {
        runner.result = .failure(.cliNotFound(.claude))
        await controller.fire(message: AppState.defaultMessage, origin: .scheduled)
        XCTAssertEqual(state.cliFound[.claude], false)
    }

    /// O controller envia exatamente a mensagem recebida (o chamador resolve).
    func testEnviaAMensagemRecebida() async {
        let msg = Message(text: "bom dia", kind: .claude)
        await controller.fire(message: msg, origin: .scheduled)
        XCTAssertEqual(runner.lastMessage, msg)
    }

    /// A janela é checada na conta efetiva da mensagem (conta por mensagem):
    /// o detector recebe a pasta da conta do override, não a da conta global.
    func testJanelaChecadaNaContaDaMensagem() async throws {
        let conta = FileManager.default.temporaryDirectory
            .appendingPathComponent("conta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: conta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: conta) }
        let msg = Message(text: "oi", kind: .claude, configDir: conta.path)
        await controller.fire(message: msg, origin: .scheduled)
        XCTAssertEqual(detector.lastAccount?.standardizedFileURL, conta.standardizedFileURL)
    }

    /// Comando cru ignora o skip de janela ativa e sempre executa.
    func testComandoCruRodaMesmoComJanelaAtiva() async {
        detector.end = now.addingTimeInterval(3600)
        let msg = Message(text: "echo oi", kind: .shell)
        await controller.fire(message: msg, origin: .scheduled)
        XCTAssertEqual(runner.calls, 1)
        XCTAssertEqual(runner.lastMessage, msg)
        XCTAssertEqual(state.lastEvent,
                       FireEvent(date: now, result: .success,
                                 messageText: "echo oi", account: ".claude", origin: .scheduled))
    }

    func testRespostaSalvaENotificadaQuandoLigado() async {
        runner.result = .success("resposta do claude")
        let msg = Message(text: "resumo", kind: .claude, showResponse: true)
        await controller.fire(message: msg, origin: .scheduled)
        XCTAssertEqual(state.lastEvent?.response, "resposta do claude")
        XCTAssertEqual(notifier.responses.count, 1)
        XCTAssertEqual(notifier.responses.first?.messageText, "HiClaude: resumo")
    }

    func testRespostaIgnoradaQuandoDesligado() async {
        runner.result = .success("resposta do claude")
        await controller.fire(message: Message(text: "1+1", kind: .claude), origin: .scheduled)
        XCTAssertNil(state.lastEvent?.response)
        XCTAssertTrue(notifier.responses.isEmpty)
    }

    func testRespostaTruncadaEm4000() async {
        runner.result = .success(String(repeating: "a", count: 5000))
        let msg = Message(text: "resumo", kind: .claude, showResponse: true)
        await controller.fire(message: msg, origin: .scheduled)
        XCTAssertEqual(state.lastEvent?.response?.count, 4000)
    }

    func testRespostaVaziaNaoNotificaNemPersiste() async {
        runner.result = .success("")
        let msg = Message(text: "resumo", kind: .claude, showResponse: true)
        await controller.fire(message: msg, origin: .scheduled)
        XCTAssertNil(state.lastEvent?.response)
        XCTAssertTrue(notifier.responses.isEmpty)
    }

    // MARK: - Resumo de falha (histórico legível)

    func testFalhaLongaGravaResumoCurtoEDetalheCompleto() async {
        let stderrCompleto = """
        warning: Model metadata for `gpt-5.1-codex-mini` not found.

        ERROR: {"type":"error","status":400,"error":{"message":"The 'gpt-5.1-codex-mini' model is not supported"}}
        """
        runner.result = .failure(.failed(stderrCompleto))
        await controller.fire(message: Message(text: "1+1", kind: .codex), origin: .manual)

        guard case .failure(let message) = state.history.first?.result else {
            return XCTFail("esperava falha no histórico")
        }
        // Resumo = última linha não vazia, não o stderr inteiro.
        XCTAssertTrue(message.hasPrefix("ERROR: {\"type\":\"error\""))
        XCTAssertFalse(message.contains("warning:"))
        // Detalhe completo vai para response (vira DisclosureGroup na UI).
        XCTAssertEqual(state.history.first?.response, stderrCompleto)
    }

    func testResumoDeFalhaTruncaEm120Caracteres() {
        let linhaLonga = String(repeating: "x", count: 300)
        XCTAssertEqual(FireController.failureSummary(linhaLonga).count, 120)
    }

    func testResumoUsaUltimaLinhaNaoVazia() {
        XCTAssertEqual(FireController.failureSummary("primeira\n\núltima  \n\n"), "última")
        XCTAssertEqual(FireController.failureSummary("só uma linha"), "só uma linha")
    }

    func testErroEstruturadoNaoGanhaDetalhe() async {
        runner.result = .failure(.timeout)
        await controller.fire(message: Message(text: "1+1", kind: .claude), origin: .manual)

        guard case .failure(let message) = state.history.first?.result else {
            return XCTFail("esperava falha no histórico")
        }
        XCTAssertEqual(message, "the command did not respond within 60s")
        XCTAssertNil(state.history.first?.response)
    }

    func testErroEstruturadoUsaIdiomaPortuguesQuandoSelecionado() async {
        state.language = .portuguese
        runner.result = .failure(.timeout)
        await controller.fire(message: Message(text: "1+1", kind: .claude), origin: .manual)

        guard case .failure(let message) = state.history.first?.result else {
            return XCTFail("esperava falha no histórico")
        }
        XCTAssertEqual(message, "o comando não respondeu em 60s")
    }
}
