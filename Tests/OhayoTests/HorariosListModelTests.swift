import XCTest

@testable import Ohayo

/// Lógica pura da tela Horários: filtro, ordenação e resumo.
final class HorariosListModelTests: XCTestCase {
    private func task(name: String? = nil, text: String = "1+1",
                      kind: Message.Kind = .claude,
                      repetition: ScheduledTask.Repetition = .fixed,
                      enabled: Bool = true) -> ScheduledTask {
        ScheduledTask(uid: UUID(), name: name,
                      command: Message(text: text, kind: kind),
                      repetition: repetition, times: [600],
                      weekdays: Set(1...7), enabled: enabled)
    }

    private func row(_ task: ScheduledTask, path: String? = "/contas/a",
                     label: String? = "conta-a", next: Date? = nil) -> HorariosRow {
        HorariosRow(task: task, accountPath: path, accountLabel: label, nextFire: next)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    // MARK: Filtros

    func testFiltroPorContaCasaPeloPathEExcluiShell() {
        let a = row(task(), path: "/contas/a", label: "a")
        let b = row(task(), path: "/contas/b", label: "b")
        let shell = row(task(kind: .shell), path: nil, label: nil)
        let filter = HorariosFilter(accountPath: "/contas/a")

        let result = HorariosListModel.apply([a, b, shell], filter: filter, sort: .padrao)

        XCTAssertEqual(result.map(\.task.uid), [a.task.uid])
    }

    func testFiltroPorProvedor() {
        let claude = row(task(kind: .claude))
        let codex = row(task(kind: .codex))
        let shell = row(task(kind: .shell), path: nil, label: nil)
        let filter = HorariosFilter(kind: .codex)

        let result = HorariosListModel.apply([claude, codex, shell], filter: filter, sort: .padrao)

        XCTAssertEqual(result.map(\.task.uid), [codex.task.uid])
    }

    func testFiltroPorStatus() {
        let on = row(task(enabled: true))
        let off = row(task(enabled: false))
        let filter = HorariosFilter(enabled: false)

        let result = HorariosListModel.apply([on, off], filter: filter, sort: .padrao)

        XCTAssertEqual(result.map(\.task.uid), [off.task.uid])
    }

    func testFiltroPorTipo() {
        let contínuo = row(task(repetition: .continuous))
        let fixo = row(task(repetition: .fixed))
        let filter = HorariosFilter(repetition: .continuous)

        let result = HorariosListModel.apply([contínuo, fixo], filter: filter, sort: .padrao)

        XCTAssertEqual(result.map(\.task.uid), [contínuo.task.uid])
    }

    func testFiltrosCombinados() {
        let alvo = row(task(kind: .claude, enabled: true), path: "/contas/a", label: "a")
        let outraConta = row(task(kind: .claude, enabled: true), path: "/contas/b", label: "b")
        let desativada = row(task(kind: .claude, enabled: false), path: "/contas/a", label: "a")
        let filter = HorariosFilter(accountPath: "/contas/a", enabled: true)

        let result = HorariosListModel.apply([alvo, outraConta, desativada],
                                             filter: filter, sort: .padrao)

        XCTAssertEqual(result.map(\.task.uid), [alvo.task.uid])
    }

    func testIsActiveDetectaQualquerDimensao() {
        XCTAssertFalse(HorariosFilter().isActive)
        XCTAssertTrue(HorariosFilter(accountPath: "/x").isActive)
        XCTAssertTrue(HorariosFilter(kind: .shell).isActive)
        XCTAssertTrue(HorariosFilter(enabled: true).isActive)
        XCTAssertTrue(HorariosFilter(repetition: .fixed).isActive)
    }

    // MARK: Ordenação

    func testOrdenacaoPadraoMantemOrdemDeCriacao() {
        let a = row(task(name: "zzz"))
        let b = row(task(name: "aaa"))

        let result = HorariosListModel.apply([a, b], filter: HorariosFilter(), sort: .padrao)

        XCTAssertEqual(result.map(\.task.uid), [a.task.uid, b.task.uid])
    }

    func testOrdenacaoPorContaCaseInsensitiveComShellNoFim() {
        let shell = row(task(kind: .shell), path: nil, label: nil)
        let bruna = row(task(), path: "/contas/b", label: "Bruna")
        let ailton = row(task(), path: "/contas/a", label: "ailton")

        let result = HorariosListModel.apply([shell, bruna, ailton],
                                             filter: HorariosFilter(), sort: .conta)

        XCTAssertEqual(result.map(\.task.uid),
                       [ailton.task.uid, bruna.task.uid, shell.task.uid])
    }

    func testOrdenacaoPorProximoDisparoComSemDataNoFim() {
        let tarde = row(task(), next: date(2_000))
        let cedo = row(task(), next: date(1_000))
        let semData = row(task(enabled: false), next: nil)

        let result = HorariosListModel.apply([tarde, semData, cedo],
                                             filter: HorariosFilter(), sort: .proximoDisparo)

        XCTAssertEqual(result.map(\.task.uid),
                       [cedo.task.uid, tarde.task.uid, semData.task.uid])
    }

    func testOrdenacaoPorNomeUsaTituloResolvido() {
        // Sem nome, o título é o texto do comando.
        let comNome = row(task(name: "bbb", text: "zzz"))
        let semNome = row(task(text: "aaa"))

        let result = HorariosListModel.apply([comNome, semNome],
                                             filter: HorariosFilter(), sort: .nome)

        XCTAssertEqual(result.map(\.task.uid), [semNome.task.uid, comNome.task.uid])
    }

    func testOrdenacaoEstavelPreservaOrdemNoEmpate() {
        let primeiro = row(task(name: "igual"))
        let segundo = row(task(name: "igual"))

        let result = HorariosListModel.apply([primeiro, segundo],
                                             filter: HorariosFilter(), sort: .nome)

        XCTAssertEqual(result.map(\.task.uid), [primeiro.task.uid, segundo.task.uid])
    }

    // MARK: Título e resumo

    func testTituloPrefereNomeSenaoTextoDoComando() {
        XCTAssertEqual(HorariosListModel.title(task(name: "Renovação", text: "1+1")), "Renovação")
        XCTAssertEqual(HorariosListModel.title(task(text: "2+2")), "2+2")
    }

    func testResumoContaTotalAtivosEProximoSoDeAtivas() {
        let ativaCedo = row(task(enabled: true), next: date(1_000))
        let ativaTarde = row(task(enabled: true), next: date(2_000))
        let desativada = row(task(enabled: false), next: date(500))
        let ativaSemData = row(task(enabled: true), next: nil)

        let summary = HorariosListModel.summary([ativaCedo, ativaTarde, desativada, ativaSemData])

        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.active, 3)
        XCTAssertEqual(summary.next, date(1_000))
    }

    func testResumoSemAtivasNaoTemProximo() {
        let desativada = row(task(enabled: false), next: date(500))

        let summary = HorariosListModel.summary([desativada])

        XCTAssertEqual(summary.total, 1)
        XCTAssertEqual(summary.active, 0)
        XCTAssertNil(summary.next)
    }
}
