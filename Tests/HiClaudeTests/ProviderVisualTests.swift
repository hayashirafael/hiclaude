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

    func testCandidatosDeBundleCobremAppEmpacotadoDevETestes() {
        let urls = ProviderVisual.resourceBundleCandidates(
            mainResourceURL: URL(fileURLWithPath: "/Apps/HiYashi.app/Contents/Resources"),
            mainBundleURL: URL(fileURLWithPath: "/Apps/HiYashi.app"),
            finderResourceURL: URL(fileURLWithPath: "/repo/.build/debug/Testes.xctest/Contents/Resources"),
            finderBundleURL: URL(fileURLWithPath: "/repo/.build/debug/Testes.xctest")
        )
        XCTAssertEqual(urls.map(\.path), [
            "/Apps/HiYashi.app/Contents/Resources/HiClaude_HiClaude.bundle",
            "/Apps/HiYashi.app/HiClaude_HiClaude.bundle",
            "/repo/.build/debug/Testes.xctest/Contents/Resources/HiClaude_HiClaude.bundle",
            "/repo/.build/debug/HiClaude_HiClaude.bundle",
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
