import XCTest
@testable import HiClaude

final class SessionDetectorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_783_000_000)

    func hoursAgo(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    // Algoritmo puro de blocos

    func testSemMensagensNaoHaJanela() {
        XCTAssertNil(SessionDetector.activeBlockEnd(timestamps: [], now: now))
    }

    func testMensagemRecenteAbreJanelaDe5h() {
        let msg = hoursAgo(1)
        let end = SessionDetector.activeBlockEnd(timestamps: [msg], now: now)
        XCTAssertEqual(end, msg.addingTimeInterval(5 * 3600))
    }

    func testMensagemAntigaNaoConta() {
        XCTAssertNil(SessionDetector.activeBlockEnd(timestamps: [hoursAgo(6)], now: now))
    }

    func testBlocosEncadeadosUsamOInicioDoBlocoCorrente() {
        // Atividade contínua: bloco 1 começa há ~9h e expira; bloco 2 começa
        // na primeira mensagem após o fim do bloco 1.
        let b1first = hoursAgo(9)
        let b1end = b1first.addingTimeInterval(5 * 3600)
        let b2first = b1end.addingTimeInterval(600) // 10min após o fim do bloco 1
        let end = SessionDetector.activeBlockEnd(timestamps: [b1first, hoursAgo(7), b2first, hoursAgo(1)], now: now)
        XCTAssertEqual(end, b2first.addingTimeInterval(5 * 3600))
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
        let conta = fm.temporaryDirectory.appendingPathComponent("hiclaude-test-\(UUID().uuidString)")
        let proj = conta.appendingPathComponent("projects/proj-a")
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
        let end = await detector.activeWindowEnd(account: conta)
        XCTAssertNotNil(end)
        XCTAssertGreaterThan(end!, Date())
    }

    func testDiretorioInexistenteRetornaNil() async {
        let detector = SessionDetector(clock: SystemClock())
        let end = await detector.activeWindowEnd(
            account: URL(fileURLWithPath: "/nao/existe/\(UUID().uuidString)"))
        XCTAssertNil(end)
    }

    func testCadeiaContinuaTruncadaPelaJanelaDeVarredura() async throws {
        // Cadeia contínua (10 em 10 min) das últimas 30h: a varredura fixa de
        // 24h truncaria no meio de um bloco. O detector deve ampliar a
        // varredura e devolver o mesmo fim de bloco do histórico completo.
        let fm = FileManager.default
        let conta = fm.temporaryDirectory.appendingPathComponent("hiclaude-test-\(UUID().uuidString)")
        let proj = conta.appendingPathComponent("projects/proj-a")
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)

        // Sem fração de segundo: o formatter abaixo grava/lê só a resolução do
        // segundo (trunca ao escrever), e a regra exata agora compara
        // timestamps sem a tolerância da hora cheia — sem este truncamento
        // aqui, "agora" (com fração) nunca bateria com o valor lido do disco.
        let agora = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
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
        let end = await detector.activeWindowEnd(account: conta)
        XCTAssertNotNil(end)
        XCTAssertEqual(end, SessionDetector.activeBlockEnd(timestamps: todas, now: agora))
    }

    func testCadeiaAlemDe7DiasParaNoTetoDeLookback() async throws {
        // Cadeia contínua (10 em 10 min) das últimas ~8 dias, sem gap de 5h: o
        // loop de ampliação do lookback dobra 24h→48h→…, mas nunca acha o gap
        // de 5h à esquerda, então deve PARAR no teto (maxLookback = 7 dias) em
        // vez de crescer para sempre — e ainda devolver a janela ativa.
        let fm = FileManager.default
        let conta = fm.temporaryDirectory.appendingPathComponent("hiclaude-test-\(UUID().uuidString)")
        let proj = conta.appendingPathComponent("projects/proj-a")
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)

        let agora = Date()
        let iso = ISO8601DateFormatter()
        var linhas = ""
        var t = agora.addingTimeInterval(-8 * 24 * 3600) // 8 dias atrás
        while t <= agora {
            linhas += "{\"type\":\"user\",\"timestamp\":\"\(iso.string(from: t))\"}\n"
            t = t.addingTimeInterval(600)
        }
        try linhas.write(to: proj.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)

        let detector = SessionDetector(clock: SystemClock())
        let end = await detector.activeWindowEnd(account: conta)
        // Atividade contínua até agora → janela ativa (o teto não impede a
        // detecção; só limita o quanto se olha para trás).
        XCTAssertNotNil(end)
        XCTAssertGreaterThan(end!, agora)
    }

    func testArquivoIlegivelEIgnoradoSemBloquear() async throws {
        let fm = FileManager.default
        let conta = fm.temporaryDirectory.appendingPathComponent("hiclaude-test-\(UUID().uuidString)")
        let proj = conta.appendingPathComponent("projects/proj-a")
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)

        // "Transcript" ilegível: um diretório com extensão .jsonl (url.lines lança ao abrir)
        try fm.createDirectory(at: proj.appendingPathComponent("quebrado.jsonl"),
                               withIntermediateDirectories: true)

        let detector = SessionDetector(clock: SystemClock())
        let semJanela = await detector.activeWindowEnd(account: conta)
        XCTAssertNil(semJanela)

        // Com um arquivo válido ao lado, o ilegível não impede a detecção
        let iso = ISO8601DateFormatter()
        let recente = iso.string(from: Date().addingTimeInterval(-1800))
        try "{\"type\":\"user\",\"timestamp\":\"\(recente)\"}\n"
            .write(to: proj.appendingPathComponent("ok.jsonl"), atomically: true, encoding: .utf8)
        let comJanela = await detector.activeWindowEnd(account: conta)
        XCTAssertNotNil(comJanela)
    }

    func testVarreduraParseiaTimestampsComRuidoESemNewlineFinal() async throws {
        // Guard do reader mapeado: linhas sem timestamp intercaladas, uma linha
        // em branco, e a última linha SEM '\n' final — todas devem ser tratadas
        // e o timestamp recente detectado.
        let fm = FileManager.default
        let conta = fm.temporaryDirectory.appendingPathComponent("hiclaude-test-\(UUID().uuidString)")
        let proj = conta.appendingPathComponent("projects/proj-a")
        try fm.createDirectory(at: proj, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-1800))
        let conteudo = """
        {"type":"summary"}

        {"type":"user","timestamp":"\(iso)"}
        """ // sem '\n' no fim
        try conteudo.write(to: proj.appendingPathComponent("s.jsonl"),
                           atomically: true, encoding: .utf8)
        let detector = SessionDetector(clock: SystemClock())
        let end = await detector.activeWindowEnd(account: conta)
        XCTAssertNotNil(end)
    }

    func testJanelaComecaNaPrimeiraMensagemExata() {
        // Caso real (2026-07-12, conta claude2): primeira mensagem 19:57:15Z →
        // a janela reseta exatamente 5h depois (00:57:15Z). A heurística antiga
        // (hora cheia, técnica ccusage) daria 00:00Z — dessincronizado do /usage.
        let t = date("2026-07-12T19:57:15Z")
        let now = date("2026-07-12T20:01:00Z")
        let end = SessionDetector.activeBlockEnd(timestamps: [t], now: now)
        XCTAssertEqual(end, date("2026-07-13T00:57:15Z"))
    }

    func testContaCodexLeSessionsJsonl() async throws {
        // Conta fake .codex-teste com sessions/2026/07/09/rollout-x.jsonl
        let conta = FileManager.default.temporaryDirectory
            .appendingPathComponent(".codex-teste-\(UUID().uuidString)")
        let sessions = conta.appendingPathComponent("sessions/2026/07/09")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: conta) }
        let agora = Date()
        let iso = ISO8601DateFormatter().string(from: agora.addingTimeInterval(-60))
        try #"{"timestamp":"\#(iso)","type":"response_item"}"#
            .write(to: sessions.appendingPathComponent("rollout-1.jsonl"),
                   atomically: true, encoding: .utf8)
        let detector = SessionDetector()
        let end = await detector.activeWindowEnd(account: conta)
        XCTAssertNotNil(end) // mensagem de 1 min atrás → janela ativa
    }
}
