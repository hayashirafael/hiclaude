import XCTest
@testable import HiClaude

final class SessionDetectorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_783_000_000)

    func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

    // Algoritmo puro de blocos

    func testSemMensagensNaoHaJanela() {
        XCTAssertNil(SessionDetector.activeBlockEnd(timestamps: [], now: now))
    }

    func testMensagemRecenteAbreJanelaDe5h() {
        let msg = hoursAgo(1)
        let end = SessionDetector.activeBlockEnd(timestamps: [msg], now: now)
        XCTAssertEqual(end, SessionDetector.floorToHour(msg).addingTimeInterval(5 * 3600))
    }

    func testMensagemAntigaNaoConta() {
        XCTAssertNil(SessionDetector.activeBlockEnd(timestamps: [hoursAgo(6)], now: now))
    }

    func testBlocosEncadeadosUsamOInicioDoBlocoCorrente() {
        // Atividade contínua: bloco 1 começa há ~9h e expira; bloco 2 começa
        // na primeira mensagem após o fim do bloco 1.
        let b1first = hoursAgo(9)
        let b1end = SessionDetector.floorToHour(b1first).addingTimeInterval(5 * 3600)
        let b2first = b1end.addingTimeInterval(600) // 10min após o fim do bloco 1
        let end = SessionDetector.activeBlockEnd(timestamps: [b1first, hoursAgo(7), b2first, hoursAgo(1)], now: now)
        XCTAssertEqual(end, SessionDetector.floorToHour(b2first).addingTimeInterval(5 * 3600))
    }

    // Parsing de linha JSONL

    func testParseTimestampComFracao() {
        let line = #"{"type":"user","timestamp":"2026-07-07T10:00:00.123Z","message":{}}"#
        XCTAssertNotNil(SessionDetector.timestamp(fromLine: line))
    }

    func testParseTimestampSemFracao() {
        let line = #"{"type":"user","timestamp":"2026-07-07T10:00:00Z"}"#
        XCTAssertNotNil(SessionDetector.timestamp(fromLine: line))
    }

    func testLinhaSemTimestampRetornaNil() {
        XCTAssertNil(SessionDetector.timestamp(fromLine: "{\"type\":\"summary\"}"))
        XCTAssertNil(SessionDetector.timestamp(fromLine: "lixo não-json"))
    }

    // Integração: varredura de diretório com fixtures

    func testVarreduraDetectaJanelaAtivaEIgnoraArquivoAntigo() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hiclaude-test-\(UUID().uuidString)")
        let proj = dir.appendingPathComponent("proj-a")
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)

        let iso = ISO8601DateFormatter()
        let recent = iso.string(from: Date().addingTimeInterval(-1800))
        try "{\"type\":\"user\",\"timestamp\":\"\(recent)\"}\n"
            .write(to: proj.appendingPathComponent("sessao.jsonl"), atomically: true, encoding: .utf8)

        // Arquivo com mtime antigo deve ser ignorado sem ser lido
        let oldFile = proj.appendingPathComponent("antiga.jsonl")
        try "{\"type\":\"user\",\"timestamp\":\"\(recent)\"}\n".write(to: oldFile, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-48 * 3600)], ofItemAtPath: oldFile.path)

        let detector = SessionDetector(projectsDir: dir, clock: SystemClock())
        let end = await detector.activeWindowEnd()
        XCTAssertNotNil(end)
        XCTAssertGreaterThan(end!, Date())
    }

    func testDiretorioInexistenteRetornaNil() async {
        let detector = SessionDetector(
            projectsDir: URL(fileURLWithPath: "/nao/existe/\(UUID().uuidString)"),
            clock: SystemClock())
        let end = await detector.activeWindowEnd()
        XCTAssertNil(end)
    }
}
