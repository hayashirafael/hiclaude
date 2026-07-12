import XCTest
@testable import Ohayo

final class MenuPanelLogicTests: XCTestCase {
    let contaA = URL(fileURLWithPath: "/tmp/contaA").standardizedFileURL
    let contaB = URL(fileURLWithPath: "/tmp/contaB").standardizedFileURL
    let now = Date(timeIntervalSince1970: 1_783_000_000)

    private func task(uid: UUID = UUID(), name: String? = nil, text: String = "1+1",
                      repetition: ScheduledTask.Repetition, enabled: Bool = true) -> ScheduledTask {
        var t = ScheduledTask(uid: uid, command: Message(text: text, kind: .claude))
        t.name = name
        t.repetition = repetition
        t.enabled = enabled
        return t
    }

    // MARK: - scheduledAccounts

    func testContasComAgendamentoHabilitadoOrdenadasPorLabel() {
        let t1 = task(repetition: .continuous)
        let t2 = task(repetition: .fixed)
        let t3 = task(repetition: .fixed, enabled: false)
        let dirs = [t1.uid: contaB, t2.uid: contaA, t3.uid: contaA]
        let result = MenuPanelLogic.scheduledAccounts(
            tasks: [t1, t2, t3],
            accountDir: { dirs[$0.uid] },
            label: { $0 == self.contaA ? "alpha" : "beta" })
        XCTAssertEqual(result, [contaA, contaB]) // ordena por label, sem duplicar
    }

    // MARK: - eventName

    func testNomeExplicitoVence() {
        let t = task(name: "teste", repetition: .fixed)
        XCTAssertEqual(MenuPanelLogic.eventName(t, renewalFallbackName: "renovação"), "teste")
    }

    func testContinuoSemNomeUsaFallback() {
        let t = task(repetition: .continuous)
        XCTAssertEqual(MenuPanelLogic.eventName(t, renewalFallbackName: "renovação"), "renovação")
    }

    func testFixoSemNomeUsaTextoTruncado() {
        let longo = String(repeating: "x", count: 50)
        let t = task(text: longo, repetition: .fixed)
        XCTAssertEqual(MenuPanelLogic.eventName(t, renewalFallbackName: "renovação"),
                       String(repeating: "x", count: 30) + "…")
    }

    // MARK: - upcomingEvents

    func testUpcomingOrdenaPorDataEntreContasETipos() {
        let cont = task(repetition: .continuous)
        let fixo = task(name: "teste", repetition: .fixed)
        let dirs = [cont.uid: contaA, fixo.uid: contaB]
        let result = MenuPanelLogic.upcomingEvents(
            tasks: [cont, fixo],
            nextRenewals: [contaA: now.addingTimeInterval(7200)],
            nextTaskFires: [fixo.uid: now.addingTimeInterval(3600)],
            isPaused: { _ in false },
            accountDir: { dirs[$0.uid] }, now: now, limit: 5,
            renewalFallbackName: "renovação")
        XCTAssertEqual(result.map(\.name), ["teste", "renovação"])
        XCTAssertEqual(result.map(\.account), [contaB, contaA])
        XCTAssertEqual(result.map(\.date),
                       [now.addingTimeInterval(3600), now.addingTimeInterval(7200)])
        XCTAssertEqual(result.first?.taskUID, fixo.uid)
    }

    func testUpcomingRespeitaLimite() {
        let t1 = task(name: "a", repetition: .fixed)
        let t2 = task(name: "b", repetition: .fixed)
        let t3 = task(name: "c", repetition: .fixed)
        let result = MenuPanelLogic.upcomingEvents(
            tasks: [t1, t2, t3], nextRenewals: [:],
            nextTaskFires: [t1.uid: now.addingTimeInterval(60),
                            t2.uid: now.addingTimeInterval(120),
                            t3.uid: now.addingTimeInterval(180)],
            isPaused: { _ in false },
            accountDir: { _ in self.contaA }, now: now, limit: 2,
            renewalFallbackName: "renovação")
        XCTAssertEqual(result.map(\.name), ["a", "b"]) // só as 2 primeiras
    }

    func testUpcomingPulaContasPausadas() {
        let pausada = task(name: "pausada", repetition: .fixed)
        let ativa = task(name: "ativa", repetition: .fixed)
        let dirs = [pausada.uid: contaA, ativa.uid: contaB]
        let result = MenuPanelLogic.upcomingEvents(
            tasks: [pausada, ativa], nextRenewals: [:],
            nextTaskFires: [pausada.uid: now.addingTimeInterval(60),
                            ativa.uid: now.addingTimeInterval(120)],
            isPaused: { $0 == self.contaA },
            accountDir: { dirs[$0.uid] }, now: now, limit: 5,
            renewalFallbackName: "renovação")
        XCTAssertEqual(result.map(\.name), ["ativa"])
    }

    func testUpcomingIgnoraPassadoDesabilitadaESemData() {
        let passada = task(name: "velha", repetition: .fixed)
        let off = task(name: "off", repetition: .fixed, enabled: false)
        let semData = task(name: "aguardando", repetition: .continuous)
        let result = MenuPanelLogic.upcomingEvents(
            tasks: [passada, off, semData], nextRenewals: [:],
            nextTaskFires: [passada.uid: now.addingTimeInterval(-60),
                            off.uid: now.addingTimeInterval(60)],
            isPaused: { _ in false },
            accountDir: { _ in self.contaA }, now: now, limit: 5,
            renewalFallbackName: "renovação")
        XCTAssertEqual(result, [])
    }

    func testUpcomingMesmaContaPodeAparecerDuasVezes() {
        let t1 = task(name: "a", repetition: .fixed)
        let t2 = task(name: "b", repetition: .fixed)
        let result = MenuPanelLogic.upcomingEvents(
            tasks: [t1, t2], nextRenewals: [:],
            nextTaskFires: [t1.uid: now.addingTimeInterval(60),
                            t2.uid: now.addingTimeInterval(120)],
            isPaused: { _ in false },
            accountDir: { _ in self.contaA }, now: now, limit: 5,
            renewalFallbackName: "renovação")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.account)), [contaA])
    }

    // MARK: - emptyState

    func testEmptyStateSemAgendamentos() {
        let off = task(repetition: .fixed, enabled: false)
        let state = MenuPanelLogic.emptyState(
            tasks: [off], accountDir: { _ in self.contaA }, isPaused: { _ in false })
        XCTAssertEqual(state, .noSchedules)
    }

    func testEmptyStateTodasPausadas() {
        let t = task(repetition: .fixed)
        let state = MenuPanelLogic.emptyState(
            tasks: [t], accountDir: { _ in self.contaA }, isPaused: { _ in true })
        XCTAssertEqual(state, .allPaused)
    }

    func testEmptyStateAguardandoJanela() {
        let t = task(repetition: .continuous)
        let state = MenuPanelLogic.emptyState(
            tasks: [t], accountDir: { _ in self.contaA }, isPaused: { _ in false })
        XCTAssertEqual(state, .waiting)
    }
}
