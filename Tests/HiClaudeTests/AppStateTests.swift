import XCTest
@testable import HiClaude

@MainActor
final class AppStateTests: XCTestCase {
    func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "hiclaude-test-\(UUID().uuidString)")!
    }

    func testPrimeiraExecucaoTemDefault7h() {
        let state = AppState(defaults: freshDefaults())
        XCTAssertEqual(state.schedules.count, 1)
        XCTAssertEqual(state.schedules[0].minutes, 7 * 60)
        XCTAssertNil(state.schedules[0].messageUID)
        XCTAssertEqual(state.times, [7 * 60])
        XCTAssertFalse(state.paused)
        XCTAssertNil(state.lastEvent)
    }

    func testPersisteERestauraSchedulesPausedELastEvent() {
        let defaults = freshDefaults()
        let event = FireEvent(date: Date(timeIntervalSince1970: 1_783_000_000), result: .success)
        let a = AppState(defaults: defaults)
        a.addSchedule(minutes: 12 * 60 + 30)
        a.updateSchedule(id: a.schedules[0].id, minutes: 8 * 60)
        a.paused = true
        a.recordEvent(event)
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.times, [8 * 60, 12 * 60 + 30]) // ordenado
        XCTAssertEqual(b.schedules, a.schedules)        // ids sobrevivem
        XCTAssertTrue(b.paused)
        XCTAssertEqual(b.lastEvent, event)
    }

    /// Migração: instalações antigas guardavam `times` como [Int].
    func testMigraTimesLegadoParaSchedules() {
        let defaults = freshDefaults()
        defaults.set([9 * 60, 7 * 60], forKey: "times")
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.times, [7 * 60, 9 * 60])
        XCTAssertTrue(state.schedules.allSatisfy { $0.messageUID == nil })
    }

    func testMensagemPorHorarioComFallbackParaAtiva() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite(text: "bom dia", kind: .claude)
        let fav = state.favorites[0]
        let id = state.schedules[0].id
        state.setScheduleMessage(id: id, messageUID: fav.uid)
        XCTAssertEqual(state.resolvedMessage(for: state.schedules[0]), fav)
        XCTAssertEqual(state.resolvedMessage(forMinutes: 7 * 60), fav)
        // Sem mensagem fixa → segue a ativa.
        state.setScheduleMessage(id: id, messageUID: nil)
        XCTAssertEqual(state.resolvedMessage(for: state.schedules[0]), state.resolvedMessage)
        // Horário desconhecido → ativa.
        XCTAssertEqual(state.resolvedMessage(forMinutes: 23 * 60), state.resolvedMessage)
    }

    /// Apagar a mensagem fixa de um horário limpa a referência (volta a "Ativa").
    func testRemoverFavoritoLimpaReferenciaDoHorario() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite(text: "bom dia", kind: .claude)
        let fav = state.favorites[0]
        state.setScheduleMessage(id: state.schedules[0].id, messageUID: fav.uid)
        state.removeFavorite(fav)
        XCTAssertNil(state.schedules[0].messageUID)
        XCTAssertEqual(state.resolvedMessage(for: state.schedules[0]), AppState.defaultMessage)
    }

    func testSchedulesOrdenamPorMinutos() {
        let state = AppState(defaults: freshDefaults())
        state.addSchedule(minutes: 6 * 60)
        XCTAssertEqual(state.times, [6 * 60, 7 * 60])
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
        XCTAssertEqual(state.activeMessage, AppState.defaultMessage)
        XCTAssertEqual(state.resolvedMessage, AppState.defaultMessage)
        XCTAssertEqual(state.allMessages, [AppState.defaultMessage])
    }

    func testAddFavoritoIgnoraVazioDuplicataEDefault() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite(text: "  oi  ", kind: .claude)   // trim
        state.addFavorite(text: "oi", kind: .claude)       // duplicata
        state.addFavorite(text: "   ", kind: .claude)      // vazio
        state.addFavorite(text: "1+1", kind: .claude)      // igual ao default
        XCTAssertEqual(state.favorites, [Message(text: "oi", kind: .claude)])
        XCTAssertEqual(state.allMessages,
                       [AppState.defaultMessage, Message(text: "oi", kind: .claude)])
    }

    func testMesmoTextoComKindsDiferentesSaoFavoritosDistintos() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite(text: "deploy", kind: .claude)
        state.addFavorite(text: "deploy", kind: .shell)
        XCTAssertEqual(state.favorites,
                       [Message(text: "deploy", kind: .claude), Message(text: "deploy", kind: .shell)])
    }

    func testRemoverFavoritoAtivoVoltaAoDefault() {
        let state = AppState(defaults: freshDefaults())
        let oi = Message(text: "oi", kind: .shell)
        state.addFavorite(text: "oi", kind: .shell)
        state.setActiveMessage(oi)
        XCTAssertEqual(state.resolvedMessage, oi)
        state.removeFavorite(oi)
        XCTAssertEqual(state.activeMessage, AppState.defaultMessage)
        XCTAssertEqual(state.resolvedMessage, AppState.defaultMessage)
    }

    func testResolvedMessageCaiNoDefaultQuandoAtivoInvalido() {
        let state = AppState(defaults: freshDefaults())
        state.setActiveMessage(Message(text: "nao-existe", kind: .claude)) // rejeitado
        XCTAssertEqual(state.resolvedMessage, AppState.defaultMessage)
    }

    func testPersisteFavoritosEAtivoComKindsMistos() {
        let defaults = freshDefaults()
        let bomDia = Message(text: "bom dia", kind: .shell)
        let a = AppState(defaults: defaults)
        a.addFavorite(text: "oi", kind: .claude)
        a.addFavorite(text: "bom dia", kind: .shell)
        a.setActiveMessage(bomDia)
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.favorites,
                       [Message(text: "oi", kind: .claude), bomDia])
        XCTAssertEqual(b.activeMessage, bomDia)
        XCTAssertEqual(b.resolvedMessage, bomDia)
    }

    func testContaPadraoInicialEhDotClaude() {
        let state = AppState(defaults: freshDefaults())
        XCTAssertEqual(state.claudeConfigDir, AppState.defaultConfigDir)
        XCTAssertEqual(state.resolvedConfigDir, AppState.defaultConfigDir)
    }

    func testPersisteERestauraConta() throws {
        let defaults = freshDefaults()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("projects"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = AppState(defaults: defaults)
        a.setAccount(dir)
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.claudeConfigDir.standardizedFileURL, dir.standardizedFileURL)
        XCTAssertEqual(b.resolvedConfigDir.standardizedFileURL, dir.standardizedFileURL)
    }

    func testResolvedConfigDirCaiNoDefaultQuandoDirNaoExiste() {
        let state = AppState(defaults: freshDefaults())
        state.setAccount(URL(fileURLWithPath: "/tmp/nao-existe-\(UUID().uuidString)"))
        XCTAssertEqual(state.resolvedConfigDir, AppState.defaultConfigDir)
    }

    func testDiscoverAccountsSempreIncluiDefaultESelecionada() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("projects"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let state = AppState(defaults: freshDefaults())
        state.setAccount(dir)
        let accounts = state.discoverAccounts().map { $0.standardizedFileURL }
        XCTAssertTrue(accounts.contains(AppState.defaultConfigDir.standardizedFileURL))
        XCTAssertTrue(accounts.contains(dir.standardizedFileURL))
    }

    func testMessageConfigRoundtripCodable() throws {
        let msg = Message(text: "tarefa", kind: .claude, model: .opus, effort: .high,
                          safeMode: false, configDir: "/tmp/conta", workingDir: "/tmp/proj")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded, msg)
    }

    /// JSON antigo (sem as chaves de config) decodifica com campos nil e os
    /// `resolved*` caem nos defaults (Haiku/low/safe).
    func testMessageAntigoDecodificaComDefaults() throws {
        let legacyJSON = #"{"text":"1+1","kind":"claude"}"#.data(using: .utf8)!
        let msg = try JSONDecoder().decode(Message.self, from: legacyJSON)
        XCTAssertNil(msg.model)
        XCTAssertNil(msg.effort)
        XCTAssertNil(msg.safeMode)
        XCTAssertEqual(msg.resolvedModel, .haiku)
        XCTAssertEqual(msg.resolvedEffort, .low)
        XCTAssertTrue(msg.resolvedSafeMode)
    }

    func testAddFavoritoComConfigPersiste() {
        let defaults = freshDefaults()
        let a = AppState(defaults: defaults)
        a.addFavorite(text: "tarefa", kind: .claude, model: .sonnet, effort: .high,
                      safeMode: false, configDir: "/tmp/c", workingDir: "/tmp/p")
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.favorites.first?.model, .sonnet)
        XCTAssertEqual(b.favorites.first?.effort, .high)
        XCTAssertEqual(b.favorites.first?.safeMode, false)
        XCTAssertEqual(b.favorites.first?.configDir, "/tmp/c")
        XCTAssertEqual(b.favorites.first?.workingDir, "/tmp/p")
    }

    func testUpdateFavoritoSubstituiEMantemAtiva() {
        let state = AppState(defaults: freshDefaults())
        let old = Message(text: "tarefa", kind: .claude)
        state.addFavorite(text: "tarefa", kind: .claude)
        state.setActiveMessage(old)
        let new = Message(text: "tarefa", kind: .claude, model: .opus)
        state.updateFavorite(old, to: new)
        XCTAssertEqual(state.favorites, [new])
        XCTAssertEqual(state.activeMessage, new)
        XCTAssertEqual(state.resolvedMessage, new)
    }

    func testEffectiveConfigDirUsaOverrideValidoEFallback() throws {
        let state = AppState(defaults: freshDefaults())
        // Override para diretório válido → usa o override.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(
            state.effectiveConfigDir(for: Message(text: "x", kind: .claude, configDir: dir.path)).standardizedFileURL,
            dir.standardizedFileURL)
        // Override inexistente → fallback na conta global.
        XCTAssertEqual(
            state.effectiveConfigDir(for: Message(text: "x", kind: .claude, configDir: "/tmp/nada-\(UUID().uuidString)")),
            state.resolvedConfigDir)
        // Sem override → conta global.
        XCTAssertEqual(
            state.effectiveConfigDir(for: Message(text: "x", kind: .claude)),
            state.resolvedConfigDir)
    }

    /// Migração: instalações antigas guardavam favoritos como `[String]` e a
    /// ativa como `String`; devem virar mensagens `.claude`.
    func testMigraFormatoLegadoStringParaClaude() {
        let defaults = freshDefaults()
        defaults.set(["oi", "bom dia"], forKey: "favorites")
        defaults.set("bom dia", forKey: "activeMessage")

        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.favorites,
                       [Message(text: "oi", kind: .claude), Message(text: "bom dia", kind: .claude)])
        XCTAssertEqual(state.activeMessage, Message(text: "bom dia", kind: .claude))
        XCTAssertEqual(state.resolvedMessage, Message(text: "bom dia", kind: .claude))
    }

    func testDefaultMessageTemUIDFixo() {
        XCTAssertEqual(AppState.defaultMessage.uid,
                       UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    }

    func testFavoritoGanhaUIDEstavelEPersistido() {
        let defaults = freshDefaults()
        let a = AppState(defaults: defaults)
        a.addFavorite(text: "oi", kind: .claude)
        let uid = a.favorites[0].uid
        XCTAssertNotNil(uid)
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.favorites[0].uid, uid)
    }

    /// Migração: favoritos persistidos sem uid ganham um na carga e ele é
    /// gravado de volta imediatamente (referências horário→mensagem dependem disso).
    func testFavoritosLegadosSemUIDGanhamUIDNaCarga() {
        let defaults = freshDefaults()
        defaults.set(#"[{"text":"oi","kind":"claude"}]"#.data(using: .utf8)!, forKey: "favorites")
        let a = AppState(defaults: defaults)
        let uid = a.favorites[0].uid
        XCTAssertNotNil(uid)
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.favorites[0].uid, uid)
    }

    func testUpdateFavoritoPreservaUID() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite(text: "tarefa", kind: .claude)
        let uid = state.favorites[0].uid
        state.updateFavorite(state.favorites[0], to: Message(text: "tarefa 2", kind: .claude))
        XCTAssertEqual(state.favorites[0].uid, uid)
        XCTAssertEqual(state.favorites[0].text, "tarefa 2")
    }

    func testIgualdadeIgnoraUID() {
        var a = Message(text: "x", kind: .claude); a.uid = UUID()
        var b = Message(text: "x", kind: .claude); b.uid = UUID()
        XCTAssertEqual(a, b)
    }

    func testMessageWithUIDEncontraFavoritoEDefault() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite(text: "oi", kind: .claude)
        let uid = state.favorites[0].uid!
        XCTAssertEqual(state.message(withUID: uid), state.favorites[0])
        XCTAssertEqual(state.message(withUID: AppState.defaultMessage.uid!), AppState.defaultMessage)
        XCTAssertNil(state.message(withUID: UUID()))
    }

    func testShowResponseLegadoNilEDefaultFalse() throws {
        let legacyJSON = #"{"text":"1+1","kind":"claude"}"#.data(using: .utf8)!
        let msg = try JSONDecoder().decode(Message.self, from: legacyJSON)
        XCTAssertNil(msg.showResponse)
        XCTAssertFalse(msg.resolvedShowResponse)
    }

    func testAddFavoritoComShowResponsePersiste() {
        let defaults = freshDefaults()
        let a = AppState(defaults: defaults)
        a.addFavorite(text: "resumo", kind: .claude, showResponse: true)
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.favorites.first?.showResponse, true)
        XCTAssertTrue(b.favorites.first!.resolvedShowResponse)
    }

    func testHistoricoCapEm20MaisRecentePrimeiro() {
        let state = AppState(defaults: freshDefaults())
        for i in 0..<25 {
            state.recordEvent(FireEvent(date: Date(timeIntervalSince1970: Double(i)), result: .success))
        }
        XCTAssertEqual(state.history.count, 20)
        XCTAssertEqual(state.history.first?.date, Date(timeIntervalSince1970: 24))
        XCTAssertEqual(state.lastEvent, state.history.first)
    }

    func testHistoricoPersisteERestaura() {
        let defaults = freshDefaults()
        let a = AppState(defaults: defaults)
        a.recordEvent(FireEvent(date: Date(timeIntervalSince1970: 1), result: .success,
                                messageText: "1+1", account: ".claude", origin: .scheduled))
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.history, a.history)
    }

    /// Migração: o lastEvent persistido pela versão antiga vira o primeiro histórico.
    func testMigraLastEventLegadoParaHistorico() {
        let defaults = freshDefaults()
        let event = FireEvent(date: Date(timeIntervalSince1970: 1_783_000_000), result: .success)
        defaults.set(try? JSONEncoder().encode(event), forKey: "lastEvent")
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.history, [event])
        XCTAssertEqual(state.lastEvent, event)
    }

    /// Evento sem os campos novos (JSON legado) decodifica com nil.
    func testFireEventLegadoDecodificaComCamposNil() throws {
        let data = try JSONEncoder().encode(FireEvent(date: Date(timeIntervalSince1970: 1), result: .success))
        let decoded = try JSONDecoder().decode(FireEvent.self, from: data)
        XCTAssertNil(decoded.messageText)
        XCTAssertNil(decoded.origin)
        XCTAssertNil(decoded.response)
    }
}
