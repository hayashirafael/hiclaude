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

    // MARK: - nextEvent

    func testEventoMaisProximoEntreContinuoEFixo() {
        let cont = task(repetition: .continuous)
        let fixo = task(name: "teste", repetition: .fixed)
        let event = MenuPanelLogic.nextEvent(
            for: contaA, tasks: [cont, fixo],
            nextRenewals: [contaA: now.addingTimeInterval(7200)],
            nextTaskFires: [fixo.uid: now.addingTimeInterval(3600)],
            accountDir: { _ in self.contaA }, now: now,
            renewalFallbackName: "renovação")
        XCTAssertEqual(event?.name, "teste")
        XCTAssertEqual(event?.date, now.addingTimeInterval(3600))
    }

    func testIgnoraDatasPassadasETarefasDeOutraConta() {
        let fixoPassado = task(name: "velho", repetition: .fixed)
        let outraConta = task(name: "alheio", repetition: .fixed)
        let dirs = [fixoPassado.uid: contaA, outraConta.uid: contaB]
        let event = MenuPanelLogic.nextEvent(
            for: contaA, tasks: [fixoPassado, outraConta],
            nextRenewals: [:],
            nextTaskFires: [fixoPassado.uid: now.addingTimeInterval(-60),
                            outraConta.uid: now.addingTimeInterval(60)],
            accountDir: { dirs[$0.uid] }, now: now,
            renewalFallbackName: "renovação")
        XCTAssertNil(event)
    }

    func testTarefaDesabilitadaNaoConta() {
        let t = task(name: "off", repetition: .fixed, enabled: false)
        let event = MenuPanelLogic.nextEvent(
            for: contaA, tasks: [t], nextRenewals: [:],
            nextTaskFires: [t.uid: now.addingTimeInterval(60)],
            accountDir: { _ in self.contaA }, now: now,
            renewalFallbackName: "renovação")
        XCTAssertNil(event)
    }
}
