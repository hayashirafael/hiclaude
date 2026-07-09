import XCTest
@testable import HiClaude

@MainActor
final class AppStateTests: XCTestCase {
    func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "hiclaude-test-\(UUID().uuidString)")!
        // Sem isso, o AppState migra o scan legado da máquina real (dev pode
        // ter ~/.claude2, ~/.claude3 de verdade) e os testes ficam
        // dependentes do ambiente. Pré-semear vazio pula a migração.
        d.set([String](), forKey: "registeredAccounts")
        return d
    }

    /// `UserDefaults` isolado, mas SEM pré-semear `registeredAccounts` — usado
    /// só pelo teste que exercita a migração do scan legado no `init`, com um
    /// `home` fake injetado (nunca a home real da máquina).
    func rawDefaultsSemMigracao() -> UserDefaults {
        UserDefaults(suiteName: "hiclaude-test-\(UUID().uuidString)")!
    }

    /// Cria uma pasta de conta fake com a assinatura pedida.
    private func makeAccountDir(signature: String? = nil, subdir: String? = nil) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("conta-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let signature {
            try "{}".write(to: dir.appendingPathComponent(signature),
                           atomically: true, encoding: .utf8)
        }
        if let subdir {
            try fm.createDirectory(at: dir.appendingPathComponent(subdir),
                                   withIntermediateDirectories: true)
        }
        return dir
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

    func testAddFavoritoIgnoraVazioDuplicataEDefault() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite(text: "  oi  ", kind: .claude)   // trim
        state.addFavorite(text: "oi", kind: .claude)       // duplicata
        state.addFavorite(text: "   ", kind: .claude)      // vazio
        state.addFavorite(text: "1+1", kind: .claude)      // igual ao default
        XCTAssertEqual(state.favorites, [Message(text: "oi", kind: .claude)])
        XCTAssertEqual(state.allMessages,
                       [AppState.defaultMessage, AppState.defaultCodexMessage, Message(text: "oi", kind: .claude)])
    }

    func testAddFavoritoRetornaMensagemCriadaOuExistente() {
        let state = AppState(defaults: freshDefaults())
        let created = state.addFavorite(text: "oi", kind: .claude)
        XCTAssertEqual(created?.text, "oi")
        XCTAssertNotNil(created?.uid)

        let duplicate = state.addFavorite(text: "oi", kind: .claude)
        XCTAssertEqual(duplicate, created)

        let empty = state.addFavorite(text: "   ", kind: .claude)
        XCTAssertNil(empty)

        let sameAsDefault = state.addFavorite(text: "1+1", kind: .claude)
        XCTAssertEqual(sameAsDefault, AppState.defaultMessage)
    }

    func testMesmoTextoComKindsDiferentesSaoFavoritosDistintos() {
        let state = AppState(defaults: freshDefaults())
        state.addFavorite(text: "deploy", kind: .claude)
        state.addFavorite(text: "deploy", kind: .shell)
        XCTAssertEqual(state.favorites,
                       [Message(text: "deploy", kind: .claude), Message(text: "deploy", kind: .shell)])
    }

    /// Sem conta selecionada: descoberta sempre inclui a conta padrão embutida.
    func testDiscoverAccountsSempreIncluiDefault() {
        let state = AppState(defaults: freshDefaults())
        let accounts = state.discoverAccounts().map { $0.standardizedFileURL }
        XCTAssertTrue(accounts.contains(AppState.defaultConfigDir.standardizedFileURL))
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

    /// Sem mensagem ativa (removida): `updateFavorite` só substitui na lista.
    func testUpdateFavoritoSubstituiNaLista() {
        let state = AppState(defaults: freshDefaults())
        let old = Message(text: "tarefa", kind: .claude)
        state.addFavorite(text: "tarefa", kind: .claude)
        let new = Message(text: "tarefa", kind: .claude, model: .opus)
        state.updateFavorite(old, to: new)
        XCTAssertEqual(state.favorites, [new])
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
        // Override inexistente → fallback na conta padrão embutida.
        XCTAssertEqual(
            state.effectiveConfigDir(for: Message(text: "x", kind: .claude, configDir: "/tmp/nada-\(UUID().uuidString)")),
            AppState.defaultConfigDir)
        // Sem override → conta padrão embutida.
        XCTAssertEqual(
            state.effectiveConfigDir(for: Message(text: "x", kind: .claude)),
            AppState.defaultConfigDir)
    }

    /// Migração: favoritos legados como [String] viram mensagens .claude.
    func testMigraFavoritosLegadosString() {
        let defaults = freshDefaults()
        defaults.set(["oi", "bom dia"], forKey: "favorites")
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.favorites,
                       [Message(text: "oi", kind: .claude), Message(text: "bom dia", kind: .claude)])
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

    func testApelidoPersisteEDefineRotulo() {
        let defaults = freshDefaults()
        let dir = URL(fileURLWithPath: "/tmp/.claude9")
        let a = AppState(defaults: defaults)
        XCTAssertNil(a.alias(for: dir))
        // Sem apelido nem e-mail (dir inexistente) → rótulo cai no nome da pasta.
        XCTAssertEqual(a.label(for: dir), ".claude9")
        a.setAlias(dir, "Trabalho")
        XCTAssertEqual(a.alias(for: dir), "Trabalho")
        XCTAssertEqual(a.label(for: dir), "Trabalho")
        a.setAlias(dir, "   ") // vazio/whitespace limpa
        XCTAssertNil(a.alias(for: dir))
        let b = AppState(defaults: defaults)
        a.setAlias(dir, "Pessoal")
        let c = AppState(defaults: defaults)
        XCTAssertEqual(c.alias(for: dir), "Pessoal")
        _ = b
    }

    func testRenewalConfigPersisteEToggleOff() {
        let defaults = freshDefaults()
        let dir = URL(fileURLWithPath: "/tmp/.claude2")
        let a = AppState(defaults: defaults)
        XCTAssertNil(a.renewal(for: dir))
        a.setRenewal(dir, AccountRenewal(mode: .scheduled, anchorMinutes: 7 * 60, messageUID: nil))
        XCTAssertEqual(a.renewal(for: dir)?.mode, .scheduled)
        XCTAssertEqual(a.renewal(for: dir)?.anchorMinutes, 7 * 60)
        let b = AppState(defaults: defaults)
        XCTAssertEqual(b.renewal(for: dir)?.mode, .scheduled)
        b.setRenewal(dir, nil) // Off
        XCTAssertNil(b.renewal(for: dir))
        let c = AppState(defaults: defaults)
        XCTAssertNil(c.renewal(for: dir))
    }

    /// Migração: renewAccounts [String] vira renovação Automática.
    func testMigraRenewAccountsParaAutomatica() {
        let defaults = freshDefaults()
        defaults.set(["/tmp/.claude", "/tmp/.claude2"], forKey: "renewAccounts")
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.renewals.count, 2)
        XCTAssertEqual(state.renewal(for: URL(fileURLWithPath: "/tmp/.claude"))?.mode, .automatic)
        XCTAssertNil(state.renewal(for: URL(fileURLWithPath: "/tmp/.claude"))?.anchorMinutes)
    }

    func testResolvedRenewalMessageCaiNoDefault() {
        let state = AppState(defaults: freshDefaults())
        let dir = URL(fileURLWithPath: "/tmp/.claude2")
        state.setRenewal(dir, AccountRenewal(mode: .automatic))
        // Sem messageUID → hi mínimo.
        XCTAssertEqual(state.resolvedRenewalMessage(for: dir), AppState.defaultMessage)
        state.addFavorite(text: "deploy", kind: .claude)
        let fav = state.favorites[0]
        state.setRenewal(dir, AccountRenewal(mode: .automatic, anchorMinutes: nil, messageUID: fav.uid))
        XCTAssertEqual(state.resolvedRenewalMessage(for: dir), fav)
    }

    func testMensagemCodexDecodificaEDefaults() throws {
        let msg = Message(text: "oi", kind: .codex)
        XCTAssertEqual(msg.resolvedCodexModel, "gpt-5.1-codex-mini")
        XCTAssertEqual(msg.resolvedCodexReasoning, .low)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded, msg)
    }

    func testMensagemLegadaSemCamposCodexDecodifica() throws {
        // JSON antigo (sem codexModel/codexReasoning) precisa decodificar.
        let json = #"{"text":"1+1","kind":"claude"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Message.self, from: json)
        XCTAssertEqual(decoded.kind, .claude)
        XCTAssertNil(decoded.codexModel)
    }

    func testHiPadraoPorProvider() {
        XCTAssertEqual(AppState.defaultHi(for: .claude), AppState.defaultMessage)
        XCTAssertEqual(AppState.defaultHi(for: .codex), AppState.defaultCodexMessage)
        XCTAssertEqual(AppState.defaultCodexMessage.kind, .codex)
        XCTAssertEqual(AppState.defaultCodexMessage.uid,
                       UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    }

    func testMessageWithUIDResolveDefaultCodex() {
        let state = AppState(defaults: freshDefaults())
        XCTAssertEqual(state.message(withUID: AppState.defaultCodexMessage.uid!),
                       AppState.defaultCodexMessage)
    }

    func testRegisterAccountInfereProviderEPersiste() throws {
        let defaults = freshDefaults()
        let state = AppState(defaults: defaults)
        let dir = try makeAccountDir(signature: "auth.json") // nome livre, conteúdo Codex
        XCTAssertEqual(state.registerAccount(dir), .codex)
        XCTAssertTrue(state.registeredAccounts.contains(dir.standardizedFileURL.path))
        XCTAssertTrue(state.discoverAccounts().contains(dir.standardizedFileURL))
        // Duplicata → no-op.
        XCTAssertEqual(state.registerAccount(dir), .codex)
        XCTAssertEqual(state.registeredAccounts.filter { $0 == dir.standardizedFileURL.path }.count, 1)
    }

    func testRegisterAccountPastaSemAssinaturaNaoCadastra() throws {
        let state = AppState(defaults: freshDefaults())
        let dir = try makeAccountDir() // sem assinatura de nenhum provider
        XCTAssertNil(state.registerAccount(dir))
        XCTAssertTrue(state.registeredAccounts.isEmpty)
    }

    func testUnregisterLimpaRenovacaoEApelido() throws {
        let state = AppState(defaults: freshDefaults())
        let dir = try makeAccountDir(subdir: "projects")
        state.registerAccount(dir)
        state.setRenewal(dir, AccountRenewal(mode: .automatic))
        state.setAlias(dir, "extra")
        state.unregisterAccount(dir)
        XCTAssertTrue(state.registeredAccounts.isEmpty)
        XCTAssertNil(state.renewal(for: dir))
        XCTAssertNil(state.alias(for: dir))
    }

    func testLegacyScanEncontraContasExtrasPorConvencao() throws {
        // Migração única: ~/.claude* com projects/, excluindo o default ~/.claude.
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: home.appendingPathComponent(".claude/projects"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude2/projects"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude-vazio"),
                               withIntermediateDirectories: true) // sem projects → fora
        defer { try? fm.removeItem(at: home) }

        let found = AppState.legacyConventionScan(home: home)
        XCTAssertEqual(found, [home.appendingPathComponent(".claude2").standardizedFileURL.path])
    }

    func testProviderForFallbackClaudeParaPastaSemAssinatura() {
        let state = AppState(defaults: freshDefaults())
        // ~/.claude recém-instalado pode não ter assinatura ainda → .claude.
        XCTAssertEqual(state.provider(for: URL(fileURLWithPath: "/nao/existe")), .claude)
    }

    func testMensagemDeRenovacaoDefaultPorProvider() throws {
        let state = AppState(defaults: freshDefaults())
        let contaCodex = try makeAccountDir(signature: "auth.json")
        XCTAssertEqual(state.resolvedRenewalMessage(for: contaCodex), AppState.defaultCodexMessage)
    }

    func testEffectiveConfigDirFallbackPorProvider() {
        let state = AppState(defaults: freshDefaults())
        let msgCodex = Message(text: "1+1", kind: .codex) // sem configDir
        XCTAssertEqual(state.effectiveConfigDir(for: msgCodex), AppState.defaultCodexConfigDir)
    }

    /// Fim a fim: quando `registeredAccounts` está ausente no UserDefaults, o
    /// `init` roda o scan legado sobre a `home` injetada (nunca a real),
    /// popula `registeredAccounts` com as contas extras (excluindo o
    /// `.claude` default) e persiste — uma segunda instância sobre o mesmo
    /// `UserDefaults` não repete o scan.
    func testInitMigraScanLegadoDeHomeInjetadaEPersiste() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("home-init-\(UUID().uuidString)")
        try fm.createDirectory(at: home.appendingPathComponent(".claude/projects"),
                               withIntermediateDirectories: true) // default → excluído do scan
        try fm.createDirectory(at: home.appendingPathComponent(".claude2/projects"),
                               withIntermediateDirectories: true) // extra → deve migrar
        defer { try? fm.removeItem(at: home) }

        let defaults = rawDefaultsSemMigracao()
        XCTAssertNil(defaults.array(forKey: "registeredAccounts"),
                     "pré-condição: chave ausente para exercitar o ramo de migração")

        let extra = home.appendingPathComponent(".claude2").standardizedFileURL.path
        let state = AppState(defaults: defaults, home: home)
        XCTAssertEqual(state.registeredAccounts, [extra])

        // Persistiu no UserDefaults (não só em memória).
        let persisted = defaults.array(forKey: "registeredAccounts") as? [String]
        XCTAssertEqual(persisted, [extra])

        // Segunda instância sobre o mesmo defaults não repete o scan: mesmo
        // adicionando uma `.claude3` na home, a chave já presente é respeitada.
        try fm.createDirectory(at: home.appendingPathComponent(".claude3/projects"),
                               withIntermediateDirectories: true)
        let state2 = AppState(defaults: defaults, home: home)
        XCTAssertEqual(state2.registeredAccounts, [extra])
    }

    /// As contas padrão (~/.claude, ~/.codex) nunca são cadastradas — são
    /// auto-detectadas. `registerAccount` nelas não deve alterar
    /// `registeredAccounts`, mesmo retornando o provider detectado.
    func testRegisterAccountNaPastaPadraoNaoCadastra() {
        let state = AppState(defaults: freshDefaults())
        state.registerAccount(AppState.defaultConfigDir)
        XCTAssertTrue(state.registeredAccounts.isEmpty)

        state.registerAccount(AppState.defaultCodexConfigDir)
        XCTAssertTrue(state.registeredAccounts.isEmpty)
    }
}
