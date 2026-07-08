import XCTest
@testable import HiClaude

@MainActor
final class AppStateTests: XCTestCase {
    func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "hiclaude-test-\(UUID().uuidString)")!
    }

    func testPrimeiraExecucaoTemDefault7h() {
        let state = AppState(defaults: freshDefaults())
        XCTAssertEqual(state.times, [7 * 60])
        XCTAssertFalse(state.paused)
        XCTAssertNil(state.lastEvent)
    }

    func testPersisteERestauraTimesPausedELastEvent() {
        let defaults = freshDefaults()
        let event = FireEvent(date: Date(timeIntervalSince1970: 1_783_000_000), result: .success)

        let a = AppState(defaults: defaults)
        a.times = [12 * 60 + 30, 7 * 60] // salva ordenado
        XCTAssertEqual(a.times, [7 * 60, 12 * 60 + 30]) // ja ordenado em memoria, na mesma instancia
        a.paused = true
        a.lastEvent = event

        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.times, [7 * 60, 12 * 60 + 30])
        XCTAssertTrue(b.paused)
        XCTAssertEqual(b.lastEvent, event)
    }

    func testPersisteLastCheck() {
        let defaults = freshDefaults()
        let a = AppState(defaults: defaults)
        let mark = Date(timeIntervalSince1970: 1_783_000_000)
        a.lastCheck = mark
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.lastCheck, mark)
    }

    func testFireResultSkippedRoundtripCodable() throws {
        let event = FireEvent(date: Date(timeIntervalSince1970: 1_783_000_000),
                              result: .skipped(activeUntil: Date(timeIntervalSince1970: 1_783_010_000)))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(FireEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testFireResultFailureRoundtripCodable() throws {
        let event = FireEvent(date: Date(timeIntervalSince1970: 1_783_000_000),
                              result: .failure(message: "claude nao encontrado"))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(FireEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testMensagemPadraoInicial() {
        let state = AppState(defaults: freshDefaults())
        XCTAssertEqual(state.favorites, [])
        XCTAssertEqual(state.activeMessage, "1+1")
        XCTAssertEqual(state.resolvedMessage, "1+1")
        XCTAssertEqual(state.allMessages, ["1+1"])
    }

    func testAddFavoritoIgnoraVazioDuplicataEDefault() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite("  oi  ")            // trim
        state.addFavorite("oi")                // duplicata
        state.addFavorite("   ")               // vazio
        state.addFavorite("1+1")               // igual ao default
        XCTAssertEqual(state.favorites, ["oi"])
        XCTAssertEqual(state.allMessages, ["1+1", "oi"])
    }

    func testRemoverFavoritoAtivoVoltaAoDefault() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite("oi")
        state.setActiveMessage("oi")
        XCTAssertEqual(state.resolvedMessage, "oi")
        state.removeFavorite("oi")
        XCTAssertEqual(state.activeMessage, "1+1")
        XCTAssertEqual(state.resolvedMessage, "1+1")
    }

    func testResolvedMessageCaiNoDefaultQuandoAtivoInvalido() {
        let state = AppState(defaults: freshDefaults())
        state.setActiveMessage("nao-existe")   // rejeitado por setActiveMessage
        XCTAssertEqual(state.resolvedMessage, "1+1")
    }

    func testPersisteFavoritosEAtivo() {
        let defaults = freshDefaults()
        let a = AppState(defaults: defaults)
        a.addFavorite("oi")
        a.addFavorite("bom dia")
        a.setActiveMessage("bom dia")
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.favorites, ["oi", "bom dia"])
        XCTAssertEqual(b.activeMessage, "bom dia")
        XCTAssertEqual(b.resolvedMessage, "bom dia")
    }
}
