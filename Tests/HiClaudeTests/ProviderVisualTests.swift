import XCTest
@testable import HiClaude

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
}
