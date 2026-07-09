import XCTest
@testable import HiClaude

@MainActor
final class RenewalEngineTests: XCTestCase {
    var detector: MockDetector!
    var clock: FakeClock!
    var engine: RenewalEngine!
    var renewed: [URL] = []
    /// Ancorado no relógio real: os Timers do engine armam no RunLoop de
    /// verdade — datas fake no passado fariam o timer disparar durante o teste.
    let now = Date()
    let conta = URL(fileURLWithPath: "/tmp/conta-renew").standardizedFileURL

    override func setUp() async throws {
        detector = MockDetector()
        clock = FakeClock(now: now)
        engine = RenewalEngine(detector: detector, clock: clock)
        renewed = []
        engine.onRenew = { [weak self] url in
            self?.renewed.append(url)
            return true
        }
    }

    func testArmaNoFimDaJanelaAtiva() async {
        detector.end = now.addingTimeInterval(3600)
        await engine.configure(accounts: [conta], paused: false)
        XCTAssertEqual(engine.nextRenewal[conta], now.addingTimeInterval(3600))
        XCTAssertTrue(renewed.isEmpty)
    }

    /// Sem janela ativa: fica armado aguardando o próximo hi, sem renovar.
    func testSemJanelaAguardaSemRenovar() async {
        detector.end = nil
        await engine.configure(accounts: [conta], paused: false)
        XCTAssertNil(engine.nextRenewal[conta])
        XCTAssertTrue(renewed.isEmpty)
    }

    /// Catch-up: a janela venceu enquanto o Mac dormia → renova ao acordar.
    func testCatchUpRenovaQuandoJanelaVenceuDormindo() async {
        detector.end = now.addingTimeInterval(3600)
        await engine.configure(accounts: [conta], paused: false)
        clock.now = now.addingTimeInterval(2 * 3600)
        detector.end = nil
        await engine.handleWake()
        XCTAssertEqual(renewed, [conta])
    }

    /// Depois de renovar, re-arma no fim da janela recém-aberta (encadeia).
    func testRenovacaoEncadeiaProximaJanela() async {
        detector.end = now.addingTimeInterval(3600)
        await engine.configure(accounts: [conta], paused: false)
        clock.now = now.addingTimeInterval(2 * 3600)
        detector.end = nil
        engine.onRenew = { [weak self] url in
            guard let self else { return true }
            self.renewed.append(url)
            self.detector.end = self.clock.now.addingTimeInterval(5 * 3600) // hi abriu janela nova
            return true
        }
        await engine.handleWake()
        XCTAssertEqual(renewed, [conta])
        XCTAssertEqual(engine.nextRenewal[conta], clock.now.addingTimeInterval(5 * 3600))
    }

    /// Se o disparo colide com outro fire em andamento (FireController.fire
    /// retorna false pelo guard isRunning), a renovação não pode marcar dedupe
    /// nem ficar travada para sempre: rearmAll() (statusTick, wake, outro
    /// fire) precisa tentar de novo depois.
    func testRenovacaoDescartadaPorIsRunningTentaDeNovo() async {
        detector.end = now.addingTimeInterval(3600)
        await engine.configure(accounts: [conta], paused: false)
        clock.now = now.addingTimeInterval(2 * 3600)
        detector.end = nil // sem janela nova ainda: a renovação é quem abriria
        var attempts = 0
        engine.onRenew = { [weak self] url in
            attempts += 1
            guard attempts > 1 else { return false } // primeira tentativa colide com isRunning
            self?.renewed.append(url)
            self?.detector.end = self?.clock.now.addingTimeInterval(5 * 3600)
            return true
        }
        await engine.handleWake() // catch-up: tenta renovar, mas é descartada
        XCTAssertTrue(renewed.isEmpty)
        XCTAssertNil(engine.nextRenewal[conta])

        await engine.rearmAll() // statusTick/outro fire tentam de novo
        XCTAssertEqual(renewed, [conta])
        XCTAssertEqual(engine.nextRenewal[conta], clock.now.addingTimeInterval(5 * 3600))
    }

    func testPausadoNaoArmaNemRenova() async {
        detector.end = now.addingTimeInterval(3600)
        await engine.configure(accounts: [conta], paused: true)
        XCTAssertNil(engine.nextRenewal[conta])
        clock.now = now.addingTimeInterval(2 * 3600)
        await engine.handleWake()
        XCTAssertTrue(renewed.isEmpty)
    }

    /// Segundo wake logo após a renovação não renova de novo.
    func testWakeConsecutivoNaoRenovaDeNovo() async {
        detector.end = now.addingTimeInterval(60)
        await engine.configure(accounts: [conta], paused: false)
        clock.now = now.addingTimeInterval(120)
        detector.end = nil
        await engine.handleWake() // catch-up renova
        await engine.handleWake() // nada armado, nada perdido
        XCTAssertEqual(renewed, [conta])
    }

    func testContaDesmarcadaEhDesarmada() async {
        detector.end = now.addingTimeInterval(3600)
        await engine.configure(accounts: [conta], paused: false)
        XCTAssertNotNil(engine.nextRenewal[conta])
        await engine.configure(accounts: [], paused: false)
        XCTAssertNil(engine.nextRenewal[conta])
    }
}
