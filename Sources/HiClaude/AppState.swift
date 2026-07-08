import Foundation

enum FireResult: Codable, Equatable {
    case success
    case skipped(activeUntil: Date)
    case failure(message: String)
}

struct FireEvent: Codable, Equatable {
    let date: Date
    let result: FireResult
}

/// Uma mensagem agendável. `claude` vira o corpo de `claude -p`; `shell` roda
/// como comando cru no shell de login (utilidade fora do Claude).
struct Message: Codable, Equatable, Identifiable {
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

    /// Id estável para ForEach; o \u{1} é separador seguro (não aparece em texto).
    /// Inclui a config para não colidir quando dois favoritos têm o mesmo texto
    /// com configs diferentes.
    var id: String {
        [kind.rawValue, text, model?.rawValue ?? "", effort?.rawValue ?? "",
         safeMode.map(String.init) ?? "", configDir ?? "", workingDir ?? ""]
            .joined(separator: "\u{1}")
    }
}

extension Message {
    static let defaultModel: Model = .haiku
    static let defaultEffort: Effort = .low
    static let defaultSafeMode = true
    var resolvedModel: Model { model ?? Self.defaultModel }
    var resolvedEffort: Effort { effort ?? Self.defaultEffort }
    var resolvedSafeMode: Bool { safeMode ?? Self.defaultSafeMode }
}

@MainActor
final class AppState: ObservableObject {
    @Published var times: [Int] {
        didSet {
            let sorted = times.sorted()
            if times != sorted { times = sorted; return } // re-normaliza uma vez; didSet re-dispara, entao igual -> persiste
            defaults.set(times, forKey: Keys.times)
        }
    }
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: Keys.paused) } }
    @Published var lastEvent: FireEvent? {
        didSet { defaults.set(lastEvent.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.lastEvent) }
    }
    @Published var claudeFound = true
    @Published var activeWindowEnd: Date?

    static let defaultMessage = Message(text: "1+1", kind: .claude)

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

    func addFavorite(text: String, kind: Message.Kind,
                     model: Message.Model? = nil, effort: Message.Effort? = nil,
                     safeMode: Bool? = nil, configDir: String? = nil,
                     workingDir: String? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let msg = Message(text: t, kind: kind, model: model, effort: effort,
                          safeMode: safeMode, configDir: configDir, workingDir: workingDir)
        guard !t.isEmpty, msg != Self.defaultMessage, !favorites.contains(msg) else { return }
        favorites.append(msg)
    }

    /// Substitui um favorito por uma versão editada. Preserva a posição na lista
    /// e mantém a seleção ativa se a mensagem editada era a ativa.
    func updateFavorite(_ old: Message, to new: Message) {
        guard let idx = favorites.firstIndex(of: old) else { return }
        let wasActive = activeMessage == old
        favorites[idx] = new
        if wasActive { activeMessage = new }
    }

    func removeFavorite(_ msg: Message) {
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

    var lastCheck: Date? {
        get { defaults.object(forKey: Keys.lastCheck) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastCheck) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let times = "times"
        static let paused = "paused"
        static let lastEvent = "lastEvent"
        static let lastCheck = "lastCheck"
        static let favorites = "favorites"
        static let activeMessage = "activeMessage"
        static let claudeConfigDir = "claudeConfigDir"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.times = (defaults.array(forKey: Keys.times) as? [Int]) ?? [7 * 60]
        self.paused = defaults.bool(forKey: Keys.paused)
        if let data = defaults.data(forKey: Keys.lastEvent) {
            self.lastEvent = try? JSONDecoder().decode(FireEvent.self, from: data)
        }
        self.favorites = Self.loadFavorites(defaults)
        self.activeMessage = Self.loadActiveMessage(defaults)
        if let path = defaults.string(forKey: Keys.claudeConfigDir) {
            self.claudeConfigDir = URL(fileURLWithPath: path)
        } else {
            self.claudeConfigDir = Self.defaultConfigDir
        }
    }

    /// Decodifica favoritos em JSON; se falhar, migra do formato legado
    /// (`[String]`, todos tratados como `.claude`).
    private static func loadFavorites(_ defaults: UserDefaults) -> [Message] {
        if let data = defaults.data(forKey: Keys.favorites),
           let decoded = try? JSONDecoder().decode([Message].self, from: data) {
            return decoded
        }
        if let legacy = defaults.array(forKey: Keys.favorites) as? [String] {
            return legacy.map { Message(text: $0, kind: .claude) }
        }
        return []
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
