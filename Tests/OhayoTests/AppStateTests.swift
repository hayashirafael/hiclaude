import XCTest
@testable import Ohayo

@MainActor
final class AppStateTests: XCTestCase {
    func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "ohayo-test-\(UUID().uuidString)")!
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
        UserDefaults(suiteName: "ohayo-test-\(UUID().uuidString)")!
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

    func testFireResultMissedRoundtripCodable() throws {
        let event = FireEvent(date: Date(timeIntervalSince1970: 1_783_000_000),
                              result: .missed(occurrence: Date(timeIntervalSince1970: 1_782_990_000)))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(FireEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    /// Histórico persistido por versões SEM o caso `missed` continua
    /// decodificando — o Codable sintetizado decodifica por chave presente.
    func testHistoricoLegadoDecodificaComCasoMissedNoEnum() throws {
        let legado = """
        [{"date":773190000,"result":{"success":{}}},
         {"date":773190060,"result":{"skipped":{"activeUntil":773200000}}},
         {"date":773190120,"result":{"failure":{"message":"exit 1"}}}]
        """.data(using: .utf8)!
        let eventos = try JSONDecoder().decode([FireEvent].self, from: legado)
        XCTAssertEqual(eventos.count, 3)
        XCTAssertEqual(eventos[0].result, .success)
        XCTAssertEqual(eventos[2].result, .failure(message: "exit 1"))
    }

    // MARK: - Heartbeat e ocorrências perdidas com o app fechado

    private var calSP: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }

    private func dateSP(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calSP.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func fixedTask(times: [Int], weekdays: Set<Int> = Set(1...7),
                           enabled: Bool = true,
                           repetition: ScheduledTask.Repetition = .fixed) -> ScheduledTask {
        var t = ScheduledTask(uid: UUID(), repetition: repetition,
                              times: times, weekdays: weekdays)
        t.enabled = enabled
        return t
    }

    func testRecordAlivePersisteHeartbeatParaOProximoLaunch() {
        let d = freshDefaults()
        let s1 = AppState(defaults: d)
        XCTAssertNil(s1.previousAliveAt) // primeiro launch de todos
        let t = dateSP(2026, 7, 9, 10, 0)
        s1.recordAlive(now: t)
        let s2 = AppState(defaults: d)
        XCTAssertEqual(s2.previousAliveAt, t)
    }

    func testRecordEventAvancaHeartbeat() {
        let d = freshDefaults()
        let s1 = AppState(defaults: d)
        let when = dateSP(2026, 7, 9, 11, 0)
        s1.recordEvent(FireEvent(date: when, result: .success))
        let s2 = AppState(defaults: d)
        XCTAssertEqual(s2.previousAliveAt, when)
    }

    func testMissedWhileClosedRegistraEventoPerdido() {
        let d = freshDefaults()
        d.set(dateSP(2026, 7, 8, 23, 0), forKey: "lastAliveAt") // app fechado às 23:00 de ontem
        let s = AppState(defaults: d)
        s.tasks = [fixedTask(times: [480])] // 08:00 diário
        s.recordMissedWhileClosed(now: dateSP(2026, 7, 9, 9, 0), calendar: calSP)
        guard case .missed(let occurrence) = s.history.first?.result else {
            return XCTFail("esperava evento .missed, veio \(String(describing: s.history.first))")
        }
        XCTAssertEqual(occurrence, dateSP(2026, 7, 9, 8, 0))
        XCTAssertEqual(s.history.first?.origin, .agenda)
        XCTAssertEqual(s.history.first?.account, ".claude") // conta padrão do provider
    }

    func testMissedWhileClosedPrimeiroLaunchNaoRegistra() {
        let s = AppState(defaults: freshDefaults()) // sem heartbeat semeado
        s.tasks = [fixedTask(times: [480])]
        s.recordMissedWhileClosed(now: dateSP(2026, 7, 9, 9, 0), calendar: calSP)
        XCTAssertTrue(s.history.isEmpty)
    }

    func testMissedWhileClosedSemOcorrenciaNoIntervaloNaoRegistra() {
        let d = freshDefaults()
        d.set(dateSP(2026, 7, 9, 8, 55), forKey: "lastAliveAt") // fechado por 5 min
        let s = AppState(defaults: d)
        s.tasks = [fixedTask(times: [480])] // 08:00 — fora do intervalo
        s.recordMissedWhileClosed(now: dateSP(2026, 7, 9, 9, 0), calendar: calSP)
        XCTAssertTrue(s.history.isEmpty)
    }

    func testMissedWhileClosedNoMaximoUmEventoPorTarefaPorLaunch() {
        let d = freshDefaults()
        d.set(dateSP(2026, 7, 8, 23, 0), forKey: "lastAliveAt")
        let s = AppState(defaults: d)
        s.tasks = [fixedTask(times: [480, 500])] // 08:00 e 08:20 perdidas
        s.recordMissedWhileClosed(now: dateSP(2026, 7, 9, 9, 0), calendar: calSP)
        XCTAssertEqual(s.history.count, 1) // só a mais recente (catch-up único)
        s.recordMissedWhileClosed(now: dateSP(2026, 7, 9, 9, 5), calendar: calSP)
        XCTAssertEqual(s.history.count, 1) // segunda chamada não duplica
    }

    func testMissedWhileClosedIgnoraDesabilitadaEContinua() {
        let d = freshDefaults()
        d.set(dateSP(2026, 7, 8, 23, 0), forKey: "lastAliveAt")
        let s = AppState(defaults: d)
        s.tasks = [fixedTask(times: [480], enabled: false),
                   fixedTask(times: [480], repetition: .continuous)]
        s.recordMissedWhileClosed(now: dateSP(2026, 7, 9, 9, 0), calendar: calSP)
        XCTAssertTrue(s.history.isEmpty)
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

    func testDefaultMessageTemUIDFixo() {
        XCTAssertEqual(AppState.defaultMessage.uid,
                       UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    }

    func testIgualdadeIgnoraUID() {
        var a = Message(text: "x", kind: .claude); a.uid = UUID()
        var b = Message(text: "x", kind: .claude); b.uid = UUID()
        XCTAssertEqual(a, b)
    }

    func testShowResponseLegadoNilEDefaultFalse() throws {
        let legacyJSON = #"{"text":"1+1","kind":"claude"}"#.data(using: .utf8)!
        let msg = try JSONDecoder().decode(Message.self, from: legacyJSON)
        XCTAssertNil(msg.showResponse)
        XCTAssertFalse(msg.resolvedShowResponse)
    }

    func testNotifyOnSuccessLegadoNilEDefaultFalse() throws {
        let legacyJSON = #"{"text":"1+1","kind":"claude"}"#.data(using: .utf8)!
        let msg = try JSONDecoder().decode(Message.self, from: legacyJSON)
        XCTAssertNil(msg.notifyOnSuccess)
        XCTAssertFalse(msg.resolvedNotifyOnSuccess)
    }

    func testIgualdadeConsideraNotifyOnSuccess() throws {
        let sem = Message(text: "x", kind: .claude)
        let com = Message(text: "x", kind: .claude, notifyOnSuccess: true)
        XCTAssertNotEqual(sem, com)
        let data = try JSONEncoder().encode(com)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded, com)
    }

    func testRunInTerminalLegadoNilEDefaultTrueParaClaudeECodex() throws {
        let claudeJSON = #"{"text":"1+1","kind":"claude"}"#.data(using: .utf8)!
        let codexJSON = #"{"text":"1+1","kind":"codex"}"#.data(using: .utf8)!
        let claude = try JSONDecoder().decode(Message.self, from: claudeJSON)
        let codex = try JSONDecoder().decode(Message.self, from: codexJSON)
        XCTAssertNil(claude.runInTerminal)
        XCTAssertNil(codex.runInTerminal)
        XCTAssertTrue(claude.resolvedRunInTerminal)
        XCTAssertTrue(codex.resolvedRunInTerminal)
    }

    func testRunInTerminalIgnoradoParaShell() throws {
        let msg = Message(text: "echo oi", kind: .shell, runInTerminal: true)
        XCTAssertFalse(msg.resolvedRunInTerminal)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded, msg)
        XCTAssertFalse(decoded.resolvedRunInTerminal)
    }

    func testIdiomaPadraoEhIngles() {
        let state = AppState(defaults: freshDefaults())
        XCTAssertEqual(state.language, .english)
        XCTAssertEqual(state.strings.settingsTitle, "Settings")
    }

    func testIdiomaPersiste() {
        let defaults = freshDefaults()
        let state = AppState(defaults: defaults)
        state.language = .portuguese
        let restored = AppState(defaults: defaults)
        XCTAssertEqual(restored.language, .portuguese)
        XCTAssertEqual(restored.strings.settingsTitle, "Configurações")
    }

    func testIdiomaInvalidoVoltaParaIngles() {
        let defaults = freshDefaults()
        defaults.set("fr", forKey: "language")
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.language, .english)
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

    func testHistoricoManualLegadoContinuaDecodificando() {
        let defaults = freshDefaults()
        let event = FireEvent(date: Date(timeIntervalSince1970: 2), result: .success,
                              messageText: "legado", origin: .manual)
        defaults.set(try? JSONEncoder().encode([event]), forKey: "history")
        XCTAssertEqual(AppState(defaults: defaults).history, [event])
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

    /// Migração legada: `renewAccounts [String]` vira agendamentos contínuos.
    func testMigraRenewAccountsParaAgendamentosContinuos() {
        let defaults = freshDefaults()
        defaults.set(["/tmp/.claude", "/tmp/.claude2"], forKey: "renewAccounts")
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.tasks.count, 2)
        XCTAssertTrue(state.tasks.allSatisfy { $0.repetition == .continuous })
        XCTAssertNil(defaults.object(forKey: "renewAccounts"), "chave legada removida")
    }

    func testMensagemCodexSemModeloFicaNilEFazRoundTrip() throws {
        // Sem escolha explícita, modelo/reasoning ficam nil (o Codex herda o
        // default da conta em vez de o app forçar um modelo).
        let msg = Message(text: "oi", kind: .codex)
        XCTAssertNil(msg.codexModel)
        XCTAssertNil(msg.codexReasoning)
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

    func testUnregisterLimpaCadastroEApelido() throws {
        let state = AppState(defaults: freshDefaults())
        let dir = try makeAccountDir(subdir: "projects")
        state.registerAccount(dir)
        state.setAlias(dir, "extra")
        state.unregisterAccount(dir)
        XCTAssertTrue(state.registeredAccounts.isEmpty)
        XCTAssertNil(state.alias(for: dir))
    }

    func testUnregisterDesabilitaAgendamentosDaConta() throws {
        let d = freshDefaults()
        let state = AppState(defaults: d)
        let conta = try makeAccountDir(signature: ".claude.json")
        state.registerAccount(conta)
        var cmd = Message(text: "1+1", kind: .claude)
        cmd.configDir = conta.path
        state.tasks = [ScheduledTask(uid: UUID(), command: cmd, repetition: .continuous)]
        state.unregisterAccount(conta)
        XCTAssertFalse(state.tasks[0].enabled)
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

    func testTasksPersistemEDecodificam() throws {
        let defaults = freshDefaults()
        let state = AppState(defaults: defaults)
        let task = ScheduledTask(uid: UUID(), name: "bom dia",
                                 command: Message(text: "bom dia", kind: .claude),
                                 times: [8 * 60], weekdays: [2, 3, 4, 5, 6], enabled: true)
        state.tasks = [task]
        let reloaded = AppState(defaults: defaults)
        XCTAssertEqual(reloaded.tasks, [task])
    }

    func testResolvedCommandSemComandoCaiNoDefault() {
        let task = ScheduledTask(uid: UUID(), times: [600], weekdays: [1])
        XCTAssertEqual(task.resolvedCommand, AppState.defaultMessage)
    }

    func testNextTaskEntryEscolheAMenorData() {
        let state = AppState(defaults: freshDefaults())
        let t1 = ScheduledTask(uid: UUID(), name: "a", commandUID: nil,
                               times: [480], weekdays: [2], enabled: true)
        let t2 = ScheduledTask(uid: UUID(), name: "b", commandUID: nil,
                               times: [600], weekdays: [2], enabled: true)
        state.tasks = [t1, t2]
        state.nextTaskFires = [t1.uid: Date().addingTimeInterval(7200),
                               t2.uid: Date().addingTimeInterval(3600)]
        XCTAssertEqual(state.nextTaskEntry?.task.uid, t2.uid)
    }

    // MARK: - Migração para agendamentos unificados

    func testMigraTarefaLegadaEmbutindoOFavorito() throws {
        let d = freshDefaults()
        let favUID = UUID()
        let fav = Message(text: "olá mundo", kind: .claude, model: .opus, uid: favUID)
        d.set(try JSONEncoder().encode([fav]), forKey: "favorites")
        // Tarefa no formato legado: commandUID, sem command/repetition.
        let legadoJSON = """
        [{"uid":"\(UUID().uuidString)","commandUID":"\(favUID.uuidString)",
          "times":[480],"weekdays":[2],"enabled":true}]
        """
        d.set(legadoJSON.data(using: .utf8)!, forKey: "tasks")

        let state = AppState(defaults: d)
        XCTAssertEqual(state.tasks.count, 1)
        XCTAssertEqual(state.tasks[0].resolvedCommand.text, "olá mundo")
        XCTAssertEqual(state.tasks[0].resolvedCommand.model, .opus)
        XCTAssertNil(state.tasks[0].resolvedCommand.uid, "cópia embutida não pertence à biblioteca")
        XCTAssertEqual(state.tasks[0].repetition, .fixed)
        XCTAssertNil(d.object(forKey: "favorites"), "biblioteca removida após embutir")
    }

    func testMigraTarefaLegadaSemComandoParaHiPadrao() throws {
        let d = freshDefaults()
        let legadoJSON = """
        [{"uid":"\(UUID().uuidString)","times":[600],"weekdays":[1,7],"enabled":false}]
        """
        d.set(legadoJSON.data(using: .utf8)!, forKey: "tasks")
        let state = AppState(defaults: d)
        XCTAssertEqual(state.tasks[0].resolvedCommand.text, "1+1")
        XCTAssertEqual(state.tasks[0].resolvedCommand.kind, .claude)
        XCTAssertFalse(state.tasks[0].enabled)
    }

    func testMigraRenovacaoAutomaticaParaAgendamentoContinuo() throws {
        let d = freshDefaults()
        let conta = try makeAccountDir(signature: ".claude.json")
        d.set(try JSONEncoder().encode([conta.path: AccountRenewal(mode: .automatic)]),
              forKey: "renewals")
        let state = AppState(defaults: d)
        XCTAssertEqual(state.tasks.count, 1)
        XCTAssertEqual(state.tasks[0].repetition, .continuous)
        XCTAssertEqual(state.tasks[0].resolvedCommand.configDir, conta.path)
        XCTAssertEqual(state.tasks[0].resolvedCommand.kind, .claude)
        XCTAssertTrue(state.tasks[0].enabled)
        XCTAssertNil(d.object(forKey: "renewals"), "chave legada removida")
    }

    func testMigraRenovacaoProgramadaParaQuatroHorariosFixos() throws {
        let d = freshDefaults()
        let conta = try makeAccountDir(signature: ".claude.json")
        var renewal = AccountRenewal(mode: .scheduled)
        renewal.anchorMinutes = 9 * 60 + 15 // 09:15
        d.set(try JSONEncoder().encode([conta.path: renewal]), forKey: "renewals")
        let state = AppState(defaults: d)
        XCTAssertEqual(state.tasks[0].repetition, .fixed)
        // 09:15 + 0/5/10/15h, mod 24h, ordenado: 00:15, 09:15, 14:15, 19:15.
        XCTAssertEqual(state.tasks[0].times, [15, 555, 855, 1155])
        XCTAssertEqual(state.tasks[0].weekdays, Set(1...7))
    }

    func testMigracaoRodaUmaVezSo() throws {
        let d = freshDefaults()
        let conta = try makeAccountDir(signature: ".claude.json")
        d.set(try JSONEncoder().encode([conta.path: AccountRenewal(mode: .automatic)]),
              forKey: "renewals")
        _ = AppState(defaults: d)
        let state2 = AppState(defaults: d)
        XCTAssertEqual(state2.tasks.count, 1, "segunda inicialização não duplica")
    }

    // MARK: - accountDir / activeScheduleCount

    func testAccountDirDeShellENil() {
        let state = AppState(defaults: freshDefaults())
        let task = ScheduledTask(uid: UUID(), command: Message(text: "ls", kind: .shell))
        XCTAssertNil(state.accountDir(for: task))
    }

    func testAccountDirComPastaSumidaENil() {
        let state = AppState(defaults: freshDefaults())
        var cmd = Message(text: "1+1", kind: .claude)
        cmd.configDir = "/tmp/nao-existe-\(UUID().uuidString)"
        let task = ScheduledTask(uid: UUID(), command: cmd)
        XCTAssertNil(state.accountDir(for: task))
    }

    func testAccountDirSemConfigDirCaiNoDefaultDoProvider() {
        let state = AppState(defaults: freshDefaults())
        let claude = ScheduledTask(uid: UUID(), command: Message(text: "1+1", kind: .claude))
        XCTAssertEqual(state.accountDir(for: claude),
                       AppState.defaultConfigDir.standardizedFileURL)
        let codex = ScheduledTask(uid: UUID(), command: Message(text: "1+1", kind: .codex))
        XCTAssertEqual(state.accountDir(for: codex),
                       AppState.defaultCodexConfigDir.standardizedFileURL)
    }

    func testActiveScheduleCountContaSoHabilitadosDaConta() throws {
        let state = AppState(defaults: freshDefaults())
        let conta = try makeAccountDir(signature: ".claude.json")
        var cmd = Message(text: "1+1", kind: .claude)
        cmd.configDir = conta.path
        state.tasks = [
            ScheduledTask(uid: UUID(), command: cmd, repetition: .continuous),
            ScheduledTask(uid: UUID(), command: cmd, times: [480], weekdays: Set(1...7)),
            {
                var t = ScheduledTask(uid: UUID(), command: cmd, times: [600], weekdays: [2])
                t.enabled = false
                return t
            }(),
            ScheduledTask(uid: UUID(), command: Message(text: "ls", kind: .shell)),
        ]
        XCTAssertEqual(state.activeScheduleCount(for: conta), 2)
    }

    func testConflitoDeContinuoPorConta() throws {
        let state = AppState(defaults: freshDefaults())
        let conta = try makeAccountDir(signature: ".claude.json")
        var cmd = Message(text: "1+1", kind: .claude)
        cmd.configDir = conta.path
        let existente = ScheduledTask(uid: UUID(), command: cmd, repetition: .continuous)
        state.tasks = [existente]

        var candidato = ScheduledTask(uid: UUID(), command: cmd, repetition: .continuous)
        XCTAssertTrue(state.hasContinuousConflict(candidato))
        // Editar o próprio agendamento não conflita consigo mesmo.
        candidato.uid = existente.uid
        XCTAssertFalse(state.hasContinuousConflict(candidato))
        // Repetição fixa nunca conflita.
        candidato.uid = UUID()
        candidato.repetition = .fixed
        XCTAssertFalse(state.hasContinuousConflict(candidato))
    }

    func testSetTaskEnabledRecusaSegundoContinuoNaMesmaConta() throws {
        let state = AppState(defaults: freshDefaults())
        let conta = try makeAccountDir(signature: ".claude.json")
        var cmd = Message(text: "1+1", kind: .claude)
        cmd.configDir = conta.path
        let habilitado = ScheduledTask(uid: UUID(), command: cmd, repetition: .continuous)
        var desabilitado = ScheduledTask(uid: UUID(), command: cmd, repetition: .continuous)
        desabilitado.enabled = false
        let fixo = ScheduledTask(uid: UUID(), command: cmd, times: [480], weekdays: Set(1...7))
        state.tasks = [habilitado, desabilitado, fixo]

        // Habilitar um 2º contínuo na mesma conta é recusado; o task fica off.
        XCTAssertFalse(state.setTaskEnabled(desabilitado, true))
        XCTAssertFalse(state.tasks.first { $0.uid == desabilitado.uid }!.enabled)
        // Habilitar um fixo na mesma conta é permitido.
        XCTAssertTrue(state.setTaskEnabled(fixo, true))
        // Desabilitar qualquer um é sempre permitido.
        XCTAssertTrue(state.setTaskEnabled(habilitado, false))
        XCTAssertFalse(state.tasks.first { $0.uid == habilitado.uid }!.enabled)
        // Com o 1º já off, o 2º contínuo pode ligar.
        XCTAssertTrue(state.setTaskEnabled(desabilitado, true))
    }

    func testRecordMissingFolderContinuousGravaUmaVezPorAgendamento() throws {
        let state = AppState(defaults: freshDefaults())
        var cmd = Message(text: "1+1", kind: .claude)
        cmd.configDir = "/tmp/nao-existe-\(UUID().uuidString)"
        state.tasks = [ScheduledTask(uid: UUID(), command: cmd, repetition: .continuous)]

        state.recordMissingFolderContinuous()
        XCTAssertEqual(state.history.count, 1)
        guard case .failure(let msg) = state.history.first?.result else {
            return XCTFail("esperava falha no histórico")
        }
        XCTAssertEqual(msg, state.strings.accountFolderMissingEvent)
        XCTAssertEqual(state.history.first?.origin, .renewal)
        // Idempotente: reconfigure repetido não duplica.
        state.recordMissingFolderContinuous()
        XCTAssertEqual(state.history.count, 1)
    }

    func testRecordMissingFolderContinuousIgnoraPastaExistenteEFixoEShell() throws {
        let state = AppState(defaults: freshDefaults())
        let conta = try makeAccountDir(signature: ".claude.json")
        var claudeOk = Message(text: "1+1", kind: .claude); claudeOk.configDir = conta.path
        var claudeFixo = Message(text: "1+1", kind: .claude)
        claudeFixo.configDir = "/tmp/nao-existe-\(UUID().uuidString)"
        state.tasks = [
            ScheduledTask(uid: UUID(), command: claudeOk, repetition: .continuous),
            ScheduledTask(uid: UUID(), command: claudeFixo, times: [480], weekdays: Set(1...7)),
            ScheduledTask(uid: UUID(), command: Message(text: "ls", kind: .shell), repetition: .continuous),
        ]
        state.recordMissingFolderContinuous()
        XCTAssertTrue(state.history.isEmpty)
    }

    func testEmailCacheAtualizaQuandoCredencialMuda() throws {
        let conta = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohayo-email-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: conta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: conta) }
        let config = conta.appendingPathComponent(".claude.json")
        func writeEmail(_ email: String, modificationDate: Date) throws {
            let json = ["oauthAccount": ["emailAddress": email]]
            try JSONSerialization.data(withJSONObject: json).write(to: config, options: .atomic)
            try FileManager.default.setAttributes(
                [.modificationDate: modificationDate], ofItemAtPath: config.path)
        }

        let state = AppState(defaults: freshDefaults())
        try writeEmail("antes@example.com", modificationDate: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(state.email(for: conta), "antes@example.com")
        try writeEmail("depois@example.com", modificationDate: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(state.email(for: conta), "depois@example.com")
    }

    func testEventoClaudeCapturaContaProviderModeloEIdentidade() throws {
        let conta = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohayo-event-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: conta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: conta) }
        let json = ["oauthAccount": ["emailAddress": "antes@example.com"]]
        try JSONSerialization.data(withJSONObject: json)
            .write(to: conta.appendingPathComponent(".claude.json"))
        let state = AppState(defaults: freshDefaults())
        state.setAlias(conta, "Trabalho")
        let message = Message(text: "revise", kind: .claude, model: .opus,
                              configDir: conta.path)

        let event = state.makeEvent(date: Date(timeIntervalSince1970: 1),
                                    result: .success, message: message, origin: .agenda)

        XCTAssertEqual(event.accountPath, conta.standardizedFileURL.path)
        XCTAssertEqual(event.provider, .claude)
        XCTAssertEqual(event.modelName, "Opus 4.8")
        XCTAssertEqual(event.aliasSnapshot, "Trabalho")
        XCTAssertEqual(event.emailSnapshot, "antes@example.com")
    }

    func testIdentidadeDoEventoPrefereDadosAtuaisESnapshotEhFallback() {
        let state = AppState(defaults: freshDefaults())
        let conta = URL(fileURLWithPath: "/tmp/ohayo-removida-\(UUID().uuidString)")
        let event = FireEvent(date: Date(), result: .success, account: conta.lastPathComponent,
                              accountPath: conta.path, provider: .codex,
                              modelName: "gpt-5.3-codex", aliasSnapshot: "Pessoal",
                              emailSnapshot: "snapshot@example.com")

        XCTAssertEqual(state.identity(for: event), EventIdentity(
            accountName: conta.lastPathComponent, alias: "Pessoal",
            email: "snapshot@example.com", provider: .codex,
            modelName: "gpt-5.3-codex"))

        state.setAlias(conta, "Atual")
        XCTAssertEqual(state.identity(for: event).displayName, "Atual")
    }

    func testEventoCodexEShellGuardamSomenteMetadadosAplicaveis() {
        let state = AppState(defaults: freshDefaults())
        let codex = state.makeEvent(date: Date(), result: .success,
                                    message: Message(text: "oi", kind: .codex,
                                                     codexModel: "gpt-5.3-codex"),
                                    origin: .agenda)
        XCTAssertEqual(codex.provider, .codex)
        XCTAssertEqual(codex.modelName, "gpt-5.3-codex")

        let shell = state.makeEvent(date: Date(), result: .success,
                                    message: Message(text: "echo oi", kind: .shell),
                                    origin: .agenda)
        XCTAssertNil(shell.account)
        XCTAssertNil(shell.accountPath)
        XCTAssertNil(shell.provider)
        XCTAssertNil(shell.modelName)
    }

    // MARK: - Pause por conta

    func testSetPausedPersisteEIsPausedLe() {
        let defaults = freshDefaults()
        let state = AppState(defaults: defaults)
        let dir = AppState.defaultConfigDir
        XCTAssertFalse(state.isPaused(dir))
        state.setPaused(dir, true)
        XCTAssertTrue(state.isPaused(dir))
        // Persistência: um segundo AppState no mesmo suite lê o mesmo valor.
        let reloaded = AppState(defaults: defaults)
        XCTAssertTrue(reloaded.isPaused(dir))
        state.setPaused(dir, false)
        XCTAssertFalse(state.isPaused(dir))
    }

    func testMigracaoPausedGlobalTruePausaContasAgendadas() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "paused")
        var task = ScheduledTask(uid: UUID(), command: AppState.defaultMessage)
        task.repetition = .continuous
        defaults.set(try? JSONEncoder().encode([task]), forKey: "tasks")
        let migrated = AppState(defaults: defaults)
        XCTAssertTrue(migrated.isPaused(AppState.defaultConfigDir))
        XCTAssertNil(defaults.object(forKey: "paused")) // key legada removida
        // Persistiu: um reload mantém a conta pausada.
        XCTAssertTrue(AppState(defaults: defaults).isPaused(AppState.defaultConfigDir))
    }

    func testMigracaoPausedGlobalFalseSoRemoveAKey() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "paused")
        let migrated = AppState(defaults: defaults)
        XCTAssertTrue(migrated.pausedAccounts.isEmpty)
        XCTAssertNil(defaults.object(forKey: "paused"))
    }

    func testAllScheduledAccountsPaused() {
        let defaults = freshDefaults()
        let state = AppState(defaults: defaults)
        var task = ScheduledTask(uid: UUID(), command: AppState.defaultMessage)
        task.repetition = .continuous
        state.tasks = [task]
        XCTAssertFalse(state.allScheduledAccountsPaused)
        state.setPaused(AppState.defaultConfigDir, true)
        XCTAssertTrue(state.allScheduledAccountsPaused)
        // Sem nenhuma conta agendada, não conta como "tudo pausado".
        state.tasks = []
        XCTAssertFalse(state.allScheduledAccountsPaused)
    }

    // MARK: - Filtro de conta (deep-link do painel)

    func testMatchesFilterPorAccountPath() {
        let state = AppState(defaults: freshDefaults())
        let event = FireEvent(date: Date(), result: .success,
                              accountPath: AppState.defaultConfigDir.standardizedFileURL.path)
        XCTAssertTrue(state.matchesFilter(event)) // sem filtro, tudo passa
        state.accountFilter = AppState.defaultConfigDir
        XCTAssertTrue(state.matchesFilter(event))
        state.accountFilter = AppState.defaultCodexConfigDir
        XCTAssertFalse(state.matchesFilter(event))
    }

    func testMatchesFilterLegadoPorNomeDaPasta() {
        let state = AppState(defaults: freshDefaults())
        let event = FireEvent(date: Date(), result: .success, account: ".claude")
        state.accountFilter = AppState.defaultConfigDir
        XCTAssertTrue(state.matchesFilter(event)) // sem accountPath, casa pelo nome
    }

    func testTaskMatchesFilter() {
        let state = AppState(defaults: freshDefaults())
        let task = ScheduledTask(uid: UUID(), command: AppState.defaultMessage)
        XCTAssertTrue(state.taskMatchesFilter(task))
        state.accountFilter = AppState.defaultConfigDir
        XCTAssertTrue(state.taskMatchesFilter(task))
        state.accountFilter = AppState.defaultCodexConfigDir
        XCTAssertFalse(state.taskMatchesFilter(task))
    }

    func testInitPreservaHistoricoDecodificavelQuandoUmEventoEstaCorrompido() throws {
        // Como em `tasks`: um evento corrompido no blob de histórico não pode
        // derrubar o array inteiro (que cairia no fallback do `lastEvent` e
        // perderia todo o histórico). Decode lossy: o evento ruim some, os bons
        // sobrevivem.
        let d = freshDefaults()
        let valido = FireEvent(date: Date(timeIntervalSince1970: 1_783_000_000),
                               result: .success, account: ".claude")
        let validoJSON = try String(data: JSONEncoder().encode(valido), encoding: .utf8)
            .map { $0 } ?? ""
        let blob = "[\(validoJSON),{\"lixo\":1}]"
        d.set(Data(blob.utf8), forKey: "history")

        let state = AppState(defaults: d)

        XCTAssertEqual(state.history.count, 1)
        XCTAssertEqual(state.history.first?.account, ".claude")
    }

    func testInitPreservaAgendamentosDecodificaveisQuandoUmItemEstaCorrompido() {
        // Regressão de perda de dados: o decode de [ScheduledTask] é tudo-ou-nada.
        // Um único item com raw value desconhecido (ex.: usuário criou um
        // agendamento numa build futura com um novo case de Repetition e depois
        // voltou para esta build via downgrade) fazia o array inteiro lançar,
        // apagando TODAS as renovações — e a primeira mutação persistia []
        // por cima do blob antigo. O decode deve ser lossy: o item ilegível
        // some, os bons sobrevivem.
        let d = freshDefaults()
        let bom = UUID()
        let blob = """
        [{"uid":"\(bom.uuidString)","repetition":"continuous"},
         {"uid":"\(UUID().uuidString)","repetition":"quinzenal"}]
        """
        d.set(Data(blob.utf8), forKey: "tasks")

        let state = AppState(defaults: d)

        XCTAssertEqual(state.tasks.map(\.uid), [bom])
    }
}
