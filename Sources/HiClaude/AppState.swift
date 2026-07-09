import Foundation

enum FireResult: Codable, Equatable {
    case success
    case skipped(activeUntil: Date)
    case failure(message: String)
}

enum FireOrigin: String, Codable { case scheduled, manual, renewal }

struct FireEvent: Codable, Equatable {
    let date: Date
    let result: FireResult
    // Campos novos, opcionais para decodificar eventos persistidos antigos.
    var messageText: String? = nil
    var account: String? = nil      // lastPathComponent da conta efetiva
    var origin: FireOrigin? = nil   // nil = evento legado
    var response: String? = nil     // resposta capturada (quando showResponse)
}

/// Uma mensagem agendável. `claude` vira o corpo de `claude -p`; `shell` roda
/// como comando cru no shell de login (utilidade fora do Claude).
struct Message: Codable, Identifiable {
    enum Kind: String, Codable { case claude, shell }

    /// Modelo do `claude --model`. Só relevante quando `kind == .claude`.
    enum Model: String, Codable, CaseIterable {
        case haiku, sonnet, opus
        var cliValue: String {
            switch self {
            case .haiku: return "claude-haiku-4-5"
            case .sonnet: return "claude-sonnet-5"
            case .opus: return "claude-opus-4-8"
            }
        }
        var label: String {
            switch self {
            case .haiku: return "Haiku 4.5"
            case .sonnet: return "Sonnet 5"
            case .opus: return "Opus 4.8"
            }
        }
    }

    /// Esforço do `claude --effort`. Só relevante quando `kind == .claude`.
    enum Effort: String, Codable, CaseIterable { case low, medium, high, xhigh, max }

    var text: String
    var kind: Kind
    // Config Claude (só relevante quando `kind == .claude`). Opcionais com
    // default `nil` para migrar de graça: o JSONDecoder tolera chaves ausentes
    // nos favoritos/activeMessage já persistidos, e o init memberwise
    // `Message(text:kind:)` (usado no caminho legado) continua compilando.
    var model: Model? = nil
    var effort: Effort? = nil
    var safeMode: Bool? = nil
    var configDir: String? = nil   // conta; nil = herda a global
    var workingDir: String? = nil  // nil = home
    /// Identidade estável — referências horário→mensagem sobrevivem a edições.
    /// Opcional para decodificar JSON legado; AppState garante uid em tudo que
    /// persiste. Fica fora do `==` de propósito (igualdade é por conteúdo).
    var uid: UUID? = nil
    /// Mostrar a resposta do disparo (histórico + notificação). nil = desligado.
    var showResponse: Bool? = nil

    /// Id para ForEach: uid quando presente, senão a chave de conteúdo (legado).
    var id: String { uid?.uuidString ?? contentKey }

    private var contentKey: String {
        let modelVal = model?.rawValue ?? ""
        let effortVal = effort?.rawValue ?? ""
        let safeModeVal = safeMode.map(String.init) ?? ""
        let configVal = configDir ?? ""
        let workingVal = workingDir ?? ""
        let showResponseVal = showResponse.map(String.init) ?? ""
        return [kind.rawValue, text, modelVal, effortVal, safeModeVal, configVal, workingVal, showResponseVal]
            .joined(separator: "\u{1}")
    }
}

extension Message: Equatable {
    /// Igualdade por conteúdo/config — ignora `uid`: dedupe e resolução de
    /// mensagem ativa comparam o que a mensagem FAZ, não quem ela é.
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.text == rhs.text && lhs.kind == rhs.kind && lhs.model == rhs.model
            && lhs.effort == rhs.effort && lhs.safeMode == rhs.safeMode
            && lhs.configDir == rhs.configDir && lhs.workingDir == rhs.workingDir
            && lhs.showResponse == rhs.showResponse
    }
}

extension Message {
    static let defaultModel: Model = .haiku
    static let defaultEffort: Effort = .low
    static let defaultSafeMode = true
    var resolvedModel: Model { model ?? Self.defaultModel }
    var resolvedEffort: Effort { effort ?? Self.defaultEffort }
    var resolvedSafeMode: Bool { safeMode ?? Self.defaultSafeMode }
    var resolvedShowResponse: Bool { showResponse ?? false }
}

/// Um horário diário. `messageUID` fixa uma mensagem específica; nil = segue
/// a mensagem ativa (comportamento clássico).
struct ScheduleEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var minutes: Int
    var messageUID: UUID? = nil
}

@MainActor
final class AppState: ObservableObject {
    @Published var schedules: [ScheduleEntry] {
        didSet {
            let sorted = schedules.sorted {
                ($0.minutes, $0.id.uuidString) < ($1.minutes, $1.id.uuidString)
            }
            if schedules != sorted { schedules = sorted; return } // re-normaliza; didSet re-dispara e persiste
            defaults.set(try? JSONEncoder().encode(schedules), forKey: Keys.schedules)
        }
    }

    /// Minutos ordenados — visão que o SchedulerEngine consome.
    var times: [Int] { schedules.map(\.minutes) }

    func addSchedule(minutes: Int) { schedules.append(ScheduleEntry(minutes: minutes)) }
    func removeSchedule(id: UUID) { schedules.removeAll { $0.id == id } }

    func updateSchedule(id: UUID, minutes: Int) {
        guard let i = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[i].minutes = minutes
    }

    func setScheduleMessage(id: UUID, messageUID: UUID?) {
        guard let i = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[i].messageUID = messageUID
    }

    /// Mensagem efetiva de um horário: a fixa se ainda existir, senão a ativa.
    func resolvedMessage(for entry: ScheduleEntry) -> Message {
        entry.messageUID.flatMap { message(withUID: $0) } ?? resolvedMessage
    }

    /// Versão por minutos (o engine reporta o horário que disparou). Se dois
    /// horários coincidirem em minutos, vale o primeiro (ordem estável por id).
    func resolvedMessage(forMinutes minutes: Int) -> Message {
        schedules.first { $0.minutes == minutes }.map { resolvedMessage(for: $0) }
            ?? resolvedMessage
    }

    @Published var paused: Bool { didSet { defaults.set(paused, forKey: Keys.paused) } }

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

    func recordEvent(_ event: FireEvent) { history.insert(event, at: 0) }

    @Published var claudeFound = true
    @Published var activeWindowEnd: Date?
    /// Mostrar o tempo restante da janela ("3h12") ao lado do ícone da barra.
    @Published var showRemainingInBar: Bool {
        didSet { defaults.set(showRemainingInBar, forKey: Keys.showRemainingInBar) }
    }
    /// Aba selecionada na janela de Configurações (deep-link a partir do menu).
    @Published var settingsTab: SettingsTab = .schedules

    static let defaultMessage = Message(
        text: "1+1", kind: .claude,
        uid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

    @Published var favorites: [Message] {
        didSet { defaults.set(try? JSONEncoder().encode(favorites), forKey: Keys.favorites) }
    }
    @Published var activeMessage: Message {
        didSet { defaults.set(try? JSONEncoder().encode(activeMessage), forKey: Keys.activeMessage) }
    }
    /// Conta Claude a aquecer, definida pelo diretório de config (`CLAUDE_CONFIG_DIR`).
    /// O ping e o detector usam este valor — assim ambos miram sempre a mesma conta.
    @Published var claudeConfigDir: URL {
        didSet { defaults.set(claudeConfigDir.path, forKey: Keys.claudeConfigDir) }
    }

    /// Diretório de config padrão do Claude Code (`~/.claude`).
    static var defaultConfigDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    /// Lista exibida na UI: o padrão embutido seguido dos favoritos do usuário.
    var allMessages: [Message] { [Self.defaultMessage] + favorites }

    /// Mensagem efetivamente enviada. Cai no padrão se a ativa não for válida.
    var resolvedMessage: Message {
        (activeMessage == Self.defaultMessage || favorites.contains(activeMessage))
            ? activeMessage : Self.defaultMessage
    }

    /// Conta efetivamente usada. Cai no padrão (`~/.claude`) se o diretório
    /// escolhido não existir mais — nunca aquece uma conta fantasma.
    var resolvedConfigDir: URL {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: claudeConfigDir.path, isDirectory: &isDir)
        return (exists && isDir.boolValue) ? claudeConfigDir : Self.defaultConfigDir
    }

    /// Contas descobertas: diretórios `~/.claude*` que contenham uma subpasta
    /// `projects` (assinatura de config do Claude Code). Sempre inclui o padrão
    /// e a conta atualmente selecionada, mesmo fora do padrão. Ordenado por path.
    func discoverAccounts() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var found: Set<URL> = [Self.defaultConfigDir.standardizedFileURL,
                               resolvedConfigDir.standardizedFileURL]
        if let names = try? fm.contentsOfDirectory(atPath: home.path) {
            for name in names where name.hasPrefix(".claude") {
                let dir = home.appendingPathComponent(name)
                var isDir: ObjCBool = false
                let projects = dir.appendingPathComponent("projects")
                if fm.fileExists(atPath: projects.path, isDirectory: &isDir), isDir.boolValue {
                    found.insert(dir.standardizedFileURL)
                }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    func setAccount(_ url: URL) {
        claudeConfigDir = url.standardizedFileURL
    }

    /// Contas com renovação automática ligada (paths standardizados).
    @Published var renewAccounts: [String] {
        didSet { defaults.set(renewAccounts, forKey: Keys.renewAccounts) }
    }

    func isRenewOn(_ dir: URL) -> Bool {
        renewAccounts.contains(dir.standardizedFileURL.path)
    }

    func setRenew(_ dir: URL, enabled: Bool) {
        let path = dir.standardizedFileURL.path
        if enabled {
            if !renewAccounts.contains(path) { renewAccounts.append(path) }
        } else {
            renewAccounts.removeAll { $0 == path }
        }
    }

    /// Próximas renovações por conta (espelho do RenewalEngine, para o menu e Geral).
    @Published var nextRenewals: [URL: Date] = [:]

    func addFavorite(text: String, kind: Message.Kind,
                     model: Message.Model? = nil, effort: Message.Effort? = nil,
                     safeMode: Bool? = nil, configDir: String? = nil,
                     workingDir: String? = nil, showResponse: Bool? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var msg = Message(text: t, kind: kind, model: model, effort: effort,
                          safeMode: safeMode, configDir: configDir,
                          workingDir: workingDir, showResponse: showResponse)
        guard !t.isEmpty, msg != Self.defaultMessage, !favorites.contains(msg) else { return }
        msg.uid = UUID()
        favorites.append(msg)
    }

    /// Substitui um favorito por uma versão editada. Preserva a posição na lista
    /// e mantém a seleção ativa se a mensagem editada era a ativa.
    func updateFavorite(_ old: Message, to new: Message) {
        guard let idx = favorites.firstIndex(of: old) else { return }
        let wasActive = activeMessage == old
        var updated = new
        updated.uid = favorites[idx].uid ?? UUID()
        favorites[idx] = updated
        if wasActive { activeMessage = updated }
    }

    func removeFavorite(_ msg: Message) {
        if let uid = msg.uid ?? favorites.first(where: { $0 == msg })?.uid {
            for i in schedules.indices where schedules[i].messageUID == uid {
                schedules[i].messageUID = nil
            }
        }
        favorites.removeAll { $0 == msg }
        if activeMessage == msg { activeMessage = Self.defaultMessage }
    }

    /// Conta efetiva de uma mensagem: o override da mensagem se existir e for um
    /// diretório válido, senão a conta global. Nunca aponta para conta fantasma.
    func effectiveConfigDir(for message: Message) -> URL {
        guard let path = message.configDir, !path.isEmpty else { return resolvedConfigDir }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        let ok = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        return ok ? url.standardizedFileURL : resolvedConfigDir
    }

    func setActiveMessage(_ msg: Message) {
        guard msg == Self.defaultMessage || favorites.contains(msg) else { return }
        activeMessage = msg
    }

    /// Resolve uma referência estável (uid) para a mensagem atual — default ou favorito.
    func message(withUID uid: UUID) -> Message? {
        if uid == Self.defaultMessage.uid { return Self.defaultMessage }
        return favorites.first { $0.uid == uid }
    }

    var lastCheck: Date? {
        get { defaults.object(forKey: Keys.lastCheck) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastCheck) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let times = "times"
        static let schedules = "schedules"
        static let paused = "paused"
        static let lastEvent = "lastEvent"
        static let history = "history"
        static let lastCheck = "lastCheck"
        static let favorites = "favorites"
        static let activeMessage = "activeMessage"
        static let claudeConfigDir = "claudeConfigDir"
        static let showRemainingInBar = "showRemainingInBar"
        static let renewAccounts = "renewAccounts"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.schedules = Self.loadSchedules(defaults)
        self.paused = defaults.bool(forKey: Keys.paused)
        if let data = defaults.data(forKey: Keys.history),
           let decoded = try? JSONDecoder().decode([FireEvent].self, from: data) {
            self.history = decoded
        } else if let data = defaults.data(forKey: Keys.lastEvent),
                  let event = try? JSONDecoder().decode(FireEvent.self, from: data) {
            self.history = [event] // migração da versão antiga
        } else {
            self.history = []
        }
        self.showRemainingInBar = defaults.bool(forKey: Keys.showRemainingInBar)
        self.favorites = Self.loadFavorites(defaults)
        self.activeMessage = Self.loadActiveMessage(defaults)
        if let path = defaults.string(forKey: Keys.claudeConfigDir) {
            self.claudeConfigDir = URL(fileURLWithPath: path)
        } else {
            self.claudeConfigDir = Self.defaultConfigDir
        }
        self.renewAccounts = (defaults.array(forKey: Keys.renewAccounts) as? [String]) ?? []
    }

    /// Decodifica schedules; se ausente, migra do formato legado `times: [Int]`.
    private static func loadSchedules(_ defaults: UserDefaults) -> [ScheduleEntry] {
        if let data = defaults.data(forKey: Keys.schedules),
           let decoded = try? JSONDecoder().decode([ScheduleEntry].self, from: data) {
            return decoded
        }
        if let legacy = defaults.array(forKey: Keys.times) as? [Int] {
            return legacy.sorted().map { ScheduleEntry(minutes: $0) }
        }
        return [ScheduleEntry(minutes: 7 * 60)]
    }

    /// Decodifica favoritos em JSON; se falhar, migra do formato legado
    /// (`[String]`, todos tratados como `.claude`).
    private static func loadFavorites(_ defaults: UserDefaults) -> [Message] {
        var loaded: [Message]
        if let data = defaults.data(forKey: Keys.favorites),
           let decoded = try? JSONDecoder().decode([Message].self, from: data) {
            loaded = decoded
        } else if let legacy = defaults.array(forKey: Keys.favorites) as? [String] {
            loaded = legacy.map { Message(text: $0, kind: .claude) }
        } else {
            return []
        }
        // Migração: garante uid estável persistido (referências horário→mensagem).
        if loaded.contains(where: { $0.uid == nil }) {
            for i in loaded.indices where loaded[i].uid == nil { loaded[i].uid = UUID() }
            defaults.set(try? JSONEncoder().encode(loaded), forKey: Keys.favorites)
        }
        return loaded
    }

    /// Decodifica a mensagem ativa em JSON; migra string legada para `.claude`.
    private static func loadActiveMessage(_ defaults: UserDefaults) -> Message {
        if let data = defaults.data(forKey: Keys.activeMessage),
           let decoded = try? JSONDecoder().decode(Message.self, from: data) {
            return decoded
        }
        if let legacy = defaults.string(forKey: Keys.activeMessage) {
            return Message(text: legacy, kind: .claude)
        }
        return Self.defaultMessage
    }
}
