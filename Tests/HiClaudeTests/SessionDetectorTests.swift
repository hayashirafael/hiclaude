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

        let detector = SessionDetector(clock: SystemClock())
        let end = await detector.activeWindowEnd(projectsDir: dir)
        XCTAssertNotNil(end)
        XCTAssertGreaterThan(end!, Date())
    }

    func testDiretorioInexistenteRetornaNil() async {
        let detector = SessionDetector(clock: SystemClock())
        let end = await detector.activeWindowEnd(
            projectsDir: URL(fileURLWithPath: "/nao/existe/\(UUID().uuidString)"))
        XCTAssertNil(end)
    }

    func testCadeiaContinuaTruncadaPelaJanelaDeVarredura() async throws {
        // Cadeia contínua (10 em 10 min) das últimas 30h: a varredura fixa de
        // 24h truncaria no meio de um bloco. O detector deve ampliar a
        // varredura e devolver o mesmo fim de bloco do histórico completo.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hiclaude-test-\(UUID().uuidString)")
        let proj = dir.appendingPathComponent("proj-a")
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)

        let agora = Date()
        let iso = ISO8601DateFormatter()
        var todas: [Date] = []
        var linhas = ""
        var t = agora.addingTimeInterval(-30 * 3600)
        while t <= agora {
            todas.append(t)
            linhas += "{\"type\":\"user\",\"timestamp\":\"\(iso.string(from: t))\"}\n"
            t = t.addingTimeInterval(600)
        }
        try linhas.write(to: proj.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)

        let detector = SessionDetector(clock: SystemClock())
        let end = await detector.activeWindowEnd(projectsDir: dir)
        XCTAssertNotNil(end)
        XCTAssertEqual(end, SessionDetector.activeBlockEnd(timestamps: todas, now: agora))
    }

    func testArquivoIlegivelEIgnoradoSemBloquear() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hiclaude-test-\(UUID().uuidString)")
        let proj = dir.appendingPathComponent("proj-a")
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)

        // "Transcript" ilegível: um diretório com extensão .jsonl (url.lines lança ao abrir)
        try fm.createDirectory(at: proj.appendingPathComponent("quebrado.jsonl"),
                               withIntermediateDirectories: true)

        let detector = SessionDetector(clock: SystemClock())
        let semJanela = await detector.activeWindowEnd(projectsDir: dir)
        XCTAssertNil(semJanela)

        // Com um arquivo válido ao lado, o ilegível não impede a detecção
        let iso = ISO8601DateFormatter()
        let recente = iso.string(from: Date().addingTimeInterval(-1800))
        try "{\"type\":\"user\",\"timestamp\":\"\(recente)\"}\n"
            .write(to: proj.appendingPathComponent("ok.jsonl"), atomically: true, encoding: .utf8)
        let comJanela = await detector.activeWindowEnd(projectsDir: dir)
        XCTAssertNotNil(comJanela)
    }
}
