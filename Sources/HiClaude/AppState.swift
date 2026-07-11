import Foundation

@MainActor
final class AppState: ObservableObject {
    /// Contas pausadas (path padronizado). O pause é por conta: os engines
    /// continuam armando timers; o FireController descarta o disparo.
    @Published var pausedAccounts: Set<String> {
        didSet { defaults.set(Array(pausedAccounts), forKey: Keys.pausedAccounts) }
    }

    func isPaused(_ dir: URL) -> Bool {
        pausedAccounts.contains(dir.standardizedFileURL.path)
    }

    func setPaused(_ dir: URL, _ on: Bool) {
        let key = dir.standardizedFileURL.path
        if on { pausedAccounts.insert(key) } else { pausedAccounts.remove(key) }
    }

    /// Todas as contas agendadas pausadas (e existe ao menos uma) — esmaece o
    /// glifo da barra.
    var allScheduledAccountsPaused: Bool {
        let dirs = Set(tasks.filter { $0.enabled }.compactMap { accountDir(for: $0) })
        return !dirs.isEmpty && dirs.allSatisfy { isPaused($0) }
    }

    static let historyLimit = 20

    @Published var history: [FireEvent] {
        didSet {
            if history.count > Self.historyLimit {
                history = Array(history.prefix(Self.historyLimit)) // didSet re-dispara e persiste
                return
            }
            defaults.set(try? JSONEncoder().encode(history), forKey: Keys.history)
        }
    }

    /// Último disparo — cabeçalho do menu.
    var lastEvent: FireEvent? { history.first }

    func recordEvent(_ event: FireEvent) {
        history.insert(event, at: 0)
        // Um disparo registrado também é sinal de vida: fecha a janela de até
        // 60s entre o último tick do heartbeat e um quit logo após o disparo
        // (evita falso "perdido" de ocorrência que na verdade executou).
        recordAlive(now: event.date)
    }

    /// Cria um evento com um snapshot mínimo da identidade. A UI prefere os
    /// dados atuais da conta e usa o snapshot quando ela não existe mais.
    func makeEvent(date: Date, result: FireResult, message: Message,
                   origin: FireOrigin, response: String? = nil) -> FireEvent {
        let provider: Provider?
        let accountDir: URL?
        let modelName: String?
        switch message.kind {
        case .claude:
            provider = .claude
            accountDir = explicitOrDefaultAccount(for: message, provider: .claude)
            modelName = message.resolvedModel.label
        case .codex:
            provider = .codex
            accountDir = explicitOrDefaultAccount(for: message, provider: .codex)
            let model = message.codexModel?.trimmingCharacters(in: .whitespacesAndNewlines)
            modelName = model?.isEmpty == false ? model : nil
        case .shell:
            provider = nil
            accountDir = nil
            modelName = nil
        }
        return FireEvent(
            date: date, result: result, messageText: message.text,
            account: accountDir?.lastPathComponent, origin: origin, response: response,
            accountPath: accountDir?.standardizedFileURL.path, provider: provider,
            modelName: modelName,
            aliasSnapshot: accountDir.flatMap { alias(for: $0) },
            emailSnapshot: accountDir.flatMap { email(for: $0) }
        )
    }

    /// Identidade atual do evento, com fallback para o snapshot persistido.
    func identity(for event: FireEvent) -> EventIdentity {
        let dir = accountDir(for: event)
        let currentAlias = dir.flatMap { alias(for: $0) }
        let currentEmail = dir.flatMap { email(for: $0) }
        return EventIdentity(
            accountName: dir?.lastPathComponent ?? event.account,
            alias: currentAlias ?? event.aliasSnapshot,
            email: currentEmail ?? event.emailSnapshot,
            provider: event.provider ?? dir.map { provider(for: $0) },
            modelName: event.modelName
        )
    }

    private func explicitOrDefaultAccount(for message: Message, provider: Provider) -> URL {
        if let path = message.configDir, !path.isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return provider == .codex ? Self.defaultCodexConfigDir : Self.defaultConfigDir
    }

    private func accountDir(for event: FireEvent) -> URL? {
        if let path = event.accountPath, !path.isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        guard let legacyName = event.account else { return nil }
        let matches = discoverAccounts().filter { $0.lastPathComponent == legacyName }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Momento em que o app esteve vivo pela última vez ANTES deste launch;
    /// nil no primeiro launch de todos. Consumido (uma vez) por
    /// `recordMissedWhileClosed`.
    private(set) var previousAliveAt: Date?

    /// Heartbeat de vida do app — o AppEnvironment chama a cada statusTick.
    /// Não é @Published de propósito: nada na UI observa, e publicar a cada
    /// 60s re-renderizaria o menu à toa.
    func recordAlive(now: Date = Date()) {
        defaults.set(now, forKey: Keys.lastAliveAt)
    }

    /// Registra no histórico, no máximo uma vez por tarefa por launch, a
    /// última ocorrência fixa perdida enquanto o app esteve fechado. Não
    /// dispara nada — decisão de produto: catch-up retroativo entre launches
    /// seria rajada indesejada; o usuário só precisa saber o que não rodou.
    func recordMissedWhileClosed(now: Date = Date(), calendar: Calendar = .current) {
        guard let since = previousAliveAt else { return }
        previousAliveAt = nil // idempotente: um relatório por launch
        for task in tasks where task.enabled && task.repetition == .fixed {
            guard let occurrence = AgendaMath.lastMissedOccurrence(
                times: task.times, weekdays: task.weekdays,
                between: since, and: now, calendar: calendar) else { continue }
            recordEvent(makeEvent(date: now, result: .missed(occurrence: occurrence),
                                  message: task.resolvedCommand, origin: .agenda))
        }
    }

    /// CLI encontrado por provider. Começa true para o ícone de erro não piscar
    /// enquanto a sonda de launch resolve.
    @Published var cliFound: [Provider: Bool] = [.claude: true, .codex: true]

    /// CLIs ausentes que importam: Claude sempre; Codex só quando alguma conta
    /// Codex está em renovação ou alguma tarefa da agenda usa Codex.
    var missingCLIs: [Provider] {
        Provider.allCases.filter { p in
            guard cliFound[p] == false else { return false }
            if p == .claude { return true }
            return tasks.contains { $0.enabled && $0.resolvedCommand.kind == .codex }
        }
    }

    /// Pulso periódico de UI: o menu exibe horários calculados com `Date()` em
    /// computed properties (`nextTaskEntry`, `nextFire`, `remaining`), que só
    /// reexecutam quando algum `@Published` muta e dispara `objectWillChange`.
    /// O `statusTick` do AppEnvironment incrementa este contador a cada ciclo
    /// para forçar o menu/barra a recomputar contra o tempo atual, mesmo quando
    /// nenhum disparo real aconteceu.
    @Published private(set) var uiHeartbeat: Int = 0

    func pulseUI() { uiHeartbeat &+= 1 }

    /// Próximos disparos por tarefa (espelho do TaskScheduler, para a UI).
    @Published var nextTaskFires: [UUID: Date] = [:]

    /// Próxima tarefa a disparar (para o menu da barra).
    var nextTaskEntry: (task: ScheduledTask, date: Date)? {
        let future = nextTaskFires.filter { $0.value > Date() }
        guard let entry = future.min(by: { $0.value < $1.value }),
              let task = tasks.first(where: { $0.uid == entry.key }) else { return nil }
        return (task, entry.value)
    }

    /// Mostrar o tempo restante da janela ("3h12") ao lado do ícone da barra.
    @Published var showRemainingInBar: Bool {
        didSet { defaults.set(showRemainingInBar, forKey: Keys.showRemainingInBar) }
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    var strings: L10n { L10n(language: language) }

    /// Seção selecionada na janela de Configurações (deep-link a partir do menu).
    @Published var settingsSection: SettingsSection = .contas

    /// Filtro de conta para as abas Tarefas/Histórico (deep-link do painel).
    @Published var accountFilter: URL?

    func matchesFilter(_ event: FireEvent) -> Bool {
        guard let filter = accountFilter else { return true }
        if let path = event.accountPath { return path == filter.standardizedFileURL.path }
        return event.account == filter.lastPathComponent
    }

    func taskMatchesFilter(_ task: ScheduledTask) -> Bool {
        guard let filter = accountFilter else { return true }
        return accountDir(for: task) == filter.standardizedFileURL
    }

    // nonisolated: valores imutáveis usados fora do ator (ex.:
    // `ScheduledTask.resolvedCommand`, que é um tipo não-isolado).
    nonisolated static let defaultMessage = Message(
        text: "1+1", kind: .claude,
        uid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

    /// Hi mínimo Codex — análogo ao defaultMessage, para contas Codex.
    nonisolated static let defaultCodexMessage = Message(
        text: "1+1", kind: .codex,
        uid: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

    /// Hi padrão embutido do provider (o "1+1" de cada mundo).
    static func defaultHi(for provider: Provider) -> Message {
        provider == .codex ? defaultCodexMessage : defaultMessage
    }

    /// Agendamentos (seção Horários) — a lista unificada.
    @Published var tasks: [ScheduledTask] {
        didSet { defaults.set(try? JSONEncoder().encode(tasks), forKey: Keys.tasks) }
    }

    /// Diretório de config padrão do Claude Code (`~/.claude`).
    static var defaultConfigDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    /// Diretório de config padrão do Codex (`~/.codex`).
    static var defaultCodexConfigDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    /// Cache de sessão do provider por conta (detect toca o disco; UI re-renderiza).
    private var providerCache: [String: Provider] = [:]

    /// Provider da conta pela assinatura do conteúdo, com cache por path.
    /// Fallback `.claude` para pasta sem assinatura (ex.: `~/.claude` recém-criado)
    /// — o app é sobre contas Claude antes de tudo.
    func provider(for dir: URL) -> Provider {
        let key = dir.standardizedFileURL.path
        if let cached = providerCache[key] { return cached }
        let value = Provider.detect(at: dir) ?? .claude
        providerCache[key] = value
        return value
    }

    /// Contas cadastradas pelo usuário (paths padronizados). Os defaults
    /// (~/.claude, ~/.codex) nunca entram aqui — são auto-detectados.
    @Published var registeredAccounts: [String] {
        didSet { defaults.set(registeredAccounts, forKey: Keys.registeredAccounts) }
    }

    /// Contas exibidas: `~/.claude` sempre (comportamento atual); `~/.codex`
    /// quando existe com assinatura Codex; cadastradas sempre (se a pasta sumiu,
    /// a UI avisa em vez de esconder). Ordenado por provider (Claude primeiro)
    /// e rótulo.
    func discoverAccounts() -> [URL] {
        var found: Set<URL> = [Self.defaultConfigDir.standardizedFileURL]
        if Provider.detect(at: Self.defaultCodexConfigDir) == .codex {
            found.insert(Self.defaultCodexConfigDir.standardizedFileURL)
        }
        for path in registeredAccounts {
            found.insert(URL(fileURLWithPath: path).standardizedFileURL)
        }
        return found.sorted { a, b in
            let (pa, pb) = (provider(for: a), provider(for: b))
            if pa != pb { return pa == .claude } // Claude primeiro
            return label(for: a).localizedCaseInsensitiveCompare(label(for: b)) == .orderedAscending
        }
    }

    /// Contas de um provider, na ordem de discoverAccounts.
    func accounts(for provider: Provider) -> [URL] {
        discoverAccounts().filter { self.provider(for: $0) == provider }
    }

    /// Cadastra uma pasta de conta apontada pelo usuário. Retorna o provider
    /// inferido pela assinatura, ou nil (pasta inválida — nada é persistido).
    @discardableResult
    func registerAccount(_ dir: URL) -> Provider? {
        guard let detected = Provider.detect(at: dir) else { return nil }
        let key = dir.standardizedFileURL.path
        providerCache[key] = detected
        let defaultPaths = [Self.defaultConfigDir.standardizedFileURL.path,
                            Self.defaultCodexConfigDir.standardizedFileURL.path]
        if !registeredAccounts.contains(key), !defaultPaths.contains(key) {
            registeredAccounts.append(key)
        }
        return detected
    }

    /// Remove uma conta cadastrada da lista — não toca o disco; limpa o
    /// apelido e desabilita os agendamentos que miravam a conta.
    func unregisterAccount(_ dir: URL) {
        let key = dir.standardizedFileURL.path
        registeredAccounts.removeAll { $0 == key }
        aliases[key] = nil
        for i in tasks.indices {
            if let cfg = tasks[i].resolvedCommand.configDir,
               URL(fileURLWithPath: cfg).standardizedFileURL.path == key {
                tasks[i].enabled = false
            }
        }
    }

    /// Scan legado por convenção: `~/.claude*` com subpasta `projects`,
    /// excluindo o default. Usado só na migração para `registeredAccounts`.
    static func legacyConventionScan(home: URL) -> [String] {
        let fm = FileManager.default
        let defaultPath = home.appendingPathComponent(".claude").standardizedFileURL.path
        var result: [String] = []
        if let names = try? fm.contentsOfDirectory(atPath: home.path) {
            for name in names.sorted() where name.hasPrefix(".claude") {
                let dir = home.appendingPathComponent(name)
                var isDir: ObjCBool = false
                let projects = dir.appendingPathComponent("projects")
                if fm.fileExists(atPath: projects.path, isDirectory: &isDir), isDir.boolValue,
                   dir.standardizedFileURL.path != defaultPath {
                    result.append(dir.standardizedFileURL.path)
                }
            }
        }
        return result
    }

    /// Apelido opcional por conta (chave = path padronizado). Independente da
    /// renovação estar ligada.
    @Published var aliases: [String: String] {
        didSet { defaults.set(aliases, forKey: Keys.aliases) }
    }

    /// Âncora padrão do modo Programada legado — só a migração usa.
    private static let defaultAnchorMinutes = 9 * 60

    /// Conta que um agendamento mira: o configDir do comando (se a pasta ainda
    /// existe), senão a conta padrão do provider. nil para shell (não mira
    /// conta) e para configDir cuja pasta sumiu (a UI avisa; nada dispara).
    func accountDir(for task: ScheduledTask) -> URL? {
        let cmd = task.resolvedCommand
        guard cmd.kind != .shell else { return nil }
        if let path = cmd.configDir, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            return url.standardizedFileURL
        }
        return (cmd.kind == .codex ? Self.defaultCodexConfigDir : Self.defaultConfigDir)
            .standardizedFileURL
    }

    /// Agendamentos habilitados que miram a conta — o "N agendamentos ativos"
    /// da aba Contas.
    func activeScheduleCount(for dir: URL) -> Int {
        let key = dir.standardizedFileURL
        return tasks.filter { $0.enabled && accountDir(for: $0) == key }.count
    }

    /// Já existe outro agendamento contínuo habilitado mirando a mesma conta?
    /// (Dois contínuos na mesma conta disparariam em dobro a cada janela.)
    func hasContinuousConflict(_ candidate: ScheduledTask) -> Bool {
        guard candidate.repetition == .continuous,
              let dir = accountDir(for: candidate) else { return false }
        return tasks.contains {
            $0.uid != candidate.uid && $0.enabled && $0.repetition == .continuous
                && accountDir(for: $0) == dir
        }
    }

    /// Habilita/desabilita um agendamento. Recusa (retorna false) apenas quando
    /// habilitar criaria um segundo contínuo habilitado na mesma conta — o
    /// mesmo guard do formulário, agora também no toggle da lista.
    @discardableResult
    func setTaskEnabled(_ task: ScheduledTask, _ on: Bool) -> Bool {
        guard let idx = tasks.firstIndex(where: { $0.uid == task.uid }) else { return false }
        if on, tasks[idx].repetition == .continuous, hasContinuousConflict(tasks[idx]) {
            return false
        }
        tasks[idx].enabled = on
        return true
    }

    /// uids de contínuos com pasta ausente já reportados — evita duplicar o
    /// evento a cada reconfigure.
    private var reportedMissingContinuous: Set<UUID> = []

    /// Grava no histórico, uma vez por agendamento, a falha "pasta não
    /// encontrada" de cada contínuo habilitado cujo configDir aponta para uma
    /// pasta que sumiu. Paridade com o caminho de horários fixos
    /// (`taskScheduler.onFire`), que já registra essa falha ao disparar.
    func recordMissingFolderContinuous() {
        var stillMissing: Set<UUID> = []
        for task in tasks where task.enabled && task.repetition == .continuous {
            let cmd = task.resolvedCommand
            guard cmd.kind != .shell, let path = cmd.configDir, !path.isEmpty,
                  accountDir(for: task) == nil else { continue }
            stillMissing.insert(task.uid)
            if !reportedMissingContinuous.contains(task.uid) {
                recordEvent(makeEvent(
                    date: Date(), result: .failure(message: strings.accountFolderMissingEvent),
                    message: cmd, origin: .renewal))
            }
        }
        reportedMissingContinuous = stillMissing
    }

    private struct EmailCacheEntry {
        let modificationDate: Date?
        let value: String?
    }

    /// Cache do e-mail por conta, invalidado quando o arquivo de autenticação
    /// muda (inclusive após relogin numa conta padrão).
    private var emailCache: [String: EmailCacheEntry] = [:]

    /// E-mail logado na conta (oauthAccount.emailAddress), com cache.
    func email(for dir: URL) -> String? {
        let key = dir.standardizedFileURL.path
        let identityFile = dir.appendingPathComponent(
            provider(for: dir) == .codex ? "auth.json" : ".claude.json")
        let modificationDate = try? identityFile.resourceValues(
            forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = emailCache[key], cached.modificationDate == modificationDate {
            return cached.value
        }
        let value = AccountIdentity.email(forConfigDir: dir)
        emailCache[key] = EmailCacheEntry(modificationDate: modificationDate, value: value)
        return value
    }

    func alias(for dir: URL) -> String? {
        let a = aliases[dir.standardizedFileURL.path]
        return (a?.isEmpty ?? true) ? nil : a
    }

    func setAlias(_ dir: URL, _ alias: String?) {
        let key = dir.standardizedFileURL.path
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { aliases[key] = trimmed } else { aliases[key] = nil }
    }

    /// Rótulo exibido: apelido → e-mail → nome da pasta.
    func label(for dir: URL) -> String {
        alias(for: dir) ?? email(for: dir) ?? dir.lastPathComponent
    }

    /// Próximas renovações por conta (espelho do RenewalEngine, para o menu e Geral).
    @Published var nextRenewals: [URL: Date] = [:]

    /// Fim da janela de 5h por conta agendada — alimentado pelo AppEnvironment
    /// quando o painel abre (não persistido; os cards derivam o "restante").
    @Published var windowEnds: [URL: Date] = [:]

    /// Conta efetiva de uma mensagem: o override se for diretório válido, senão
    /// a conta padrão embutida do provider da mensagem (~/.claude ou ~/.codex).
    /// Nunca aponta para conta fantasma.
    func effectiveConfigDir(for message: Message) -> URL {
        let fallback = message.kind == .codex ? Self.defaultCodexConfigDir : Self.defaultConfigDir
        guard let path = message.configDir, !path.isEmpty else { return fallback }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        let ok = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        return ok ? url.standardizedFileURL : fallback
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let paused = "paused" // legado — só a migração lê/remove
        static let pausedAccounts = "pausedAccounts"
        static let history = "history"
        static let favorites = "favorites"
        static let showRemainingInBar = "showRemainingInBar"
        static let aliases = "aliases"
        static let renewals = "renewals"
        static let registeredAccounts = "registeredAccounts"
        static let tasks = "tasks"
        static let language = "language"
        static let lastAliveAt = "lastAliveAt"
    }

    init(defaults: UserDefaults = .standard,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        self.previousAliveAt = defaults.object(forKey: Keys.lastAliveAt) as? Date
        self.pausedAccounts = Set((defaults.array(forKey: Keys.pausedAccounts) as? [String]) ?? [])
        if let data = defaults.data(forKey: Keys.history),
           let decoded = try? JSONDecoder().decode([FailableDecodable<FireEvent>].self, from: data) {
            // Decode lossy (como `tasks`): um evento corrompido some, o resto do
            // histórico sobrevive — em vez de o array inteiro lançar e o app
            // cair no fallback do `lastEvent` legado, perdendo tudo.
            self.history = decoded.compactMap(\.value)
        } else if let data = defaults.data(forKey: "lastEvent"),
                  let event = try? JSONDecoder().decode(FireEvent.self, from: data) {
            self.history = [event] // migração da versão antiga
        } else {
            self.history = []
        }
        self.showRemainingInBar = defaults.bool(forKey: Keys.showRemainingInBar)
        if let rawLanguage = defaults.string(forKey: Keys.language),
           let language = AppLanguage(rawValue: rawLanguage) {
            self.language = language
        } else {
            self.language = .english
        }
        let legacyFavorites = Self.loadLegacyFavorites(defaults)
        self.aliases = (defaults.dictionary(forKey: Keys.aliases) as? [String: String]) ?? [:]
        var loadedTasks: [ScheduledTask] = []
        if let data = defaults.data(forKey: Keys.tasks),
           let decoded = try? JSONDecoder().decode([FailableDecodable<ScheduledTask>].self, from: data) {
            // Decode lossy: um item ilegível (ex.: raw value de uma build
            // futura após downgrade) some, mas os demais agendamentos
            // sobrevivem — em vez de o array inteiro lançar e a primeira
            // mutação persistir [] por cima do blob antigo.
            loadedTasks = decoded.compactMap(\.value)
        }
        // Migração de mão única para agendamentos unificados: embute o
        // favorito nas tarefas legadas e converte renovações em agendamentos.
        var migrou = false
        for i in loadedTasks.indices where loadedTasks[i].command == nil {
            loadedTasks[i].command = Self.embeddedCommand(
                uid: loadedTasks[i].commandUID, favorites: legacyFavorites)
            loadedTasks[i].commandUID = nil
            migrou = true
        }
        let legacyRenewals = Self.loadRenewals(defaults)
        if !legacyRenewals.isEmpty {
            for (path, renewal) in legacyRenewals.sorted(by: { $0.key < $1.key }) {
                loadedTasks.append(Self.migratedRenewalTask(
                    path: path, renewal: renewal, favorites: legacyFavorites))
            }
            migrou = true
        }
        self.tasks = loadedTasks
        if migrou {
            defaults.set(try? JSONEncoder().encode(loadedTasks), forKey: Keys.tasks)
        }
        // Legado removido só DEPOIS de persistir o resultado migrado (acima):
        // um crash entre migrar e persistir apagaria o legado sem ter salvo a
        // migração, perdendo renovações/favoritos irreversivelmente.
        if defaults.object(forKey: Keys.renewals) != nil
            || defaults.object(forKey: "renewAccounts") != nil {
            defaults.removeObject(forKey: Keys.renewals)
            defaults.removeObject(forKey: "renewAccounts")
        }
        if migrou, defaults.object(forKey: Keys.favorites) != nil {
            defaults.removeObject(forKey: Keys.favorites)
        }
        if let stored = defaults.array(forKey: Keys.registeredAccounts) as? [String] {
            self.registeredAccounts = stored
        } else {
            // Migração única: quem atualizou vindo do scan por convenção mantém as
            // contas extras (ex.: ~/.claude2) sem precisar recadastrar.
            self.registeredAccounts = Self.legacyConventionScan(home: home)
            defaults.set(self.registeredAccounts, forKey: Keys.registeredAccounts)
        }
        // Migração one-way do pause global: true vira pause de cada conta
        // agendada. Atribuição dentro do init não dispara didSet — persistir
        // explicitamente.
        if defaults.object(forKey: Keys.paused) != nil {
            if defaults.bool(forKey: Keys.paused) {
                pausedAccounts = Set(tasks.filter { $0.enabled }
                    .compactMap { accountDir(for: $0)?.standardizedFileURL.path })
                defaults.set(Array(pausedAccounts), forKey: Keys.pausedAccounts)
            }
            defaults.removeObject(forKey: Keys.paused)
        }
    }

    /// LEGADO: decodifica os favoritos persistidos pela versão com biblioteca
    /// de comandos — só a migração do init lê, para embutir nos agendamentos.
    private static func loadLegacyFavorites(_ defaults: UserDefaults) -> [Message] {
        if let data = defaults.data(forKey: Keys.favorites),
           let decoded = try? JSONDecoder().decode([Message].self, from: data) {
            return decoded
        }
        if let legacy = defaults.array(forKey: Keys.favorites) as? [String] {
            return legacy.map { Message(text: $0, kind: .claude) }
        }
        return []
    }

    /// Decodifica renovações; se ausente, migra do formato legado
    /// `renewAccounts: [String]` (todas como Automática).
    private static func loadRenewals(_ defaults: UserDefaults) -> [String: AccountRenewal] {
        if let data = defaults.data(forKey: Keys.renewals),
           let decoded = try? JSONDecoder().decode([String: AccountRenewal].self, from: data) {
            return decoded
        }
        if let legacy = defaults.array(forKey: "renewAccounts") as? [String] {
            var result: [String: AccountRenewal] = [:]
            for path in legacy { result[path] = AccountRenewal(mode: .automatic) }
            return result
        }
        return [:]
    }

    /// Cópia embutida do favorito referenciado (ou hi padrão). uid zerado:
    /// o prompt passa a pertencer ao agendamento, não à biblioteca.
    private static func embeddedCommand(uid: UUID?, favorites: [Message]) -> Message {
        var msg: Message
        if let uid, uid == defaultCodexMessage.uid {
            msg = defaultCodexMessage
        } else if let uid, let fav = favorites.first(where: { $0.uid == uid }) {
            msg = fav
        } else {
            msg = defaultMessage
        }
        msg.uid = nil
        return msg
    }

    /// Renovação legada → agendamento: Automática vira contínua; Programada
    /// vira horários fixos com as 4 janelas do ciclo ancorado (âncora +
    /// 0/5/10/15h), todos os dias.
    private static func migratedRenewalTask(path: String, renewal: AccountRenewal,
                                            favorites: [Message]) -> ScheduledTask {
        let provider = Provider.detect(at: URL(fileURLWithPath: path)) ?? .claude
        var command: Message
        if let uid = renewal.messageUID, let fav = favorites.first(where: { $0.uid == uid }) {
            command = fav
        } else {
            command = defaultHi(for: provider)
        }
        command.uid = nil
        command.configDir = path
        var task = ScheduledTask(uid: UUID(), command: command)
        switch renewal.mode {
        case .automatic:
            task.repetition = .continuous
        case .scheduled:
            let anchor = renewal.anchorMinutes ?? defaultAnchorMinutes
            task.repetition = .fixed
            task.times = (0..<4).map { (anchor + $0 * 300) % 1440 }.sorted()
            task.weekdays = Set(1...7)
        }
        return task
    }
}
