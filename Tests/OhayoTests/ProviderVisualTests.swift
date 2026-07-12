import XCTest
@testable import Ohayo

@MainActor
final class ProviderVisualTests: XCTestCase {
    func testAssetsOficiaisCarregamComoTemplate() throws {
        let claude = try XCTUnwrap(ProviderVisual.image(for: .claude))
        let codex = try XCTUnwrap(ProviderVisual.image(for: .codex))
        XCTAssertTrue(claude.isTemplate)
        XCTAssertTrue(codex.isTemplate)
        XCTAssertGreaterThan(claude.size.width, 0)
        XCTAssertGreaterThan(codex.size.width, 0)
    }

    func testNovoAgendamentoComecaSemComando() {
        XCTAssertEqual(AgendamentoFormSheet.initialCommandText, "")
    }

    func testNovoAgendamentoComecaSemModoDeSaida() {
        XCTAssertEqual(AgendamentoFormSheet.initialOutputMode, .none)
    }

    func testModoDeSaidaNormalizaMensagensPersistidas() {
        XCTAssertEqual(
            AgendamentoFormSheet.outputMode(for: Message(text: "x", kind: .claude)),
            .terminal)
        XCTAssertEqual(
            AgendamentoFormSheet.outputMode(for: Message(
                text: "x", kind: .claude, showResponse: true, runInTerminal: false)),
            .response)
        XCTAssertEqual(
            AgendamentoFormSheet.outputMode(for: Message(
                text: "x", kind: .claude, runInTerminal: false)),
            .none)
        XCTAssertEqual(
            AgendamentoFormSheet.outputMode(for: Message(
                text: "x", kind: .claude, showResponse: true, runInTerminal: true)),
            .terminal)
        XCTAssertEqual(
            AgendamentoFormSheet.outputMode(for: Message(text: "echo x", kind: .shell)),
            .none)
    }

    func testRestoredStateParaNovoAgendamentoUsaDefaults() {
        let restored = AgendamentoFormSheet.restoredState(for: nil)
        XCTAssertEqual(restored.kind, .claude)
        XCTAssertNil(restored.skill)
        XCTAssertNil(restored.account)
    }

    /// Regressão do bug crítico de perda de dado: editar uma task Codex com
    /// skill configurada não pode zerar a skill antes mesmo do usuário tocar
    /// em qualquer coisa. `restoredState` é a função pura que o `init` usa
    /// para semear o `@State` de uma vez só (sem passar pelo default
    /// `.claude` e só depois corrigir para `.codex` — o que disparava
    /// `.onChange(of: kind)` à toa e limpava a skill).
    func testRestoredStatePreservaSkillDeTaskCodexEmEdicao() {
        let command = Message(text: "revisa", kind: .codex, configDir: "/contas/codex-1",
                               skill: "minha-skill")
        let task = ScheduledTask(uid: UUID(), command: command)
        let restored = AgendamentoFormSheet.restoredState(for: task)
        XCTAssertEqual(restored.kind, .codex)
        XCTAssertEqual(restored.skill, "minha-skill")
        XCTAssertEqual(restored.account, "/contas/codex-1")
    }

    /// Mesmo quando a skill configurada não existe mais na conta (pasta
    /// renomeada/apagada): `restoredState` mantém a seleção tal como
    /// persistida. É a UI (aviso "não encontrada") quem sinaliza o problema —
    /// só uma troca de tipo genuína, feita pelo usuário depois de montada a
    /// view, deve limpar a skill.
    func testRestoredStateMantemSkillMesmoQueDesconhecidaParaCatalogoAtual() {
        let command = Message(text: "revisa", kind: .claude, skill: "skill-renomeada")
        let task = ScheduledTask(uid: UUID(), command: command)
        let restored = AgendamentoFormSheet.restoredState(for: task)
        XCTAssertEqual(restored.skill, "skill-renomeada")
    }

    func testCandidatosDeBundleCobremAppEmpacotadoDevETestes() {
        let urls = ProviderVisual.resourceBundleCandidates(
            mainResourceURL: URL(fileURLWithPath: "/Apps/Ohayo.app/Contents/Resources"),
            mainBundleURL: URL(fileURLWithPath: "/Apps/Ohayo.app"),
            finderResourceURL: URL(fileURLWithPath: "/repo/.build/debug/Testes.xctest/Contents/Resources"),
            finderBundleURL: URL(fileURLWithPath: "/repo/.build/debug/Testes.xctest")
        )
        XCTAssertEqual(urls.map(\.path), [
            "/Apps/Ohayo.app/Contents/Resources/Ohayo_Ohayo.bundle",
            "/Apps/Ohayo.app/Ohayo_Ohayo.bundle",
            "/repo/.build/debug/Testes.xctest/Contents/Resources/Ohayo_Ohayo.bundle",
            "/repo/.build/debug/Ohayo_Ohayo.bundle",
        ])
    }

    func testCandidatosDeBundleIgnoramBasesAusentes() {
        let urls = ProviderVisual.resourceBundleCandidates(
            mainResourceURL: nil, mainBundleURL: nil,
            finderResourceURL: nil, finderBundleURL: nil
        )
        XCTAssertEqual(urls, [])
    }
}
