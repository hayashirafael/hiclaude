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
    enum Kind: String, Codable { case claude, shell, codex }

    /// Reasoning do Codex (`-c model_reasoning_effort`). Só relevante em `.codex`.
    enum CodexReasoning: String, Codable, CaseIterable { case minimal, low, medium, high }

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
    // nos favoritos já persistidos, e o init memberwise
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
    // Config Codex (só relevante quando `kind == .codex`). Opcionais com default
    // nil pelo mesmo motivo dos campos Claude: migração de graça.
    var codexModel: String? = nil
    var codexReasoning: CodexReasoning? = nil

    /// Id para ForEach: uid quando presente, senão a chave de conteúdo (legado).
    var id: String { uid?.uuidString ?? contentKey }

    private var contentKey: String {
        let modelVal = model?.rawValue ?? ""
        let effortVal = effort?.rawValue ?? ""
        let safeModeVal = safeMode.map(String.init) ?? ""
        let configVal = configDir ?? ""
        let workingVal = workingDir ?? ""
        let showResponseVal = showResponse.map(String.init) ?? ""
        let codexModelVal = codexModel ?? ""
        let codexReasoningVal = codexReasoning?.rawValue ?? ""
        return [kind.rawValue, text, modelVal, effortVal, safeModeVal, configVal, workingVal, showResponseVal, codexModelVal, codexReasoningVal]
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
            && lhs.codexModel == rhs.codexModel && lhs.codexReasoning == rhs.codexReasoning
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

    static let defaultCodexModel = "gpt-5.1-codex-mini"
    static let defaultCodexReasoning: CodexReasoning = .low
    var resolvedCodexModel: String { codexModel ?? Self.defaultCodexModel }
    var resolvedCodexReasoning: CodexReasoning { codexReasoning ?? Self.defaultCodexReasoning }
}

/// Configuração de renovação de uma Conta. Presença no dicionário `renewals`
/// significa "renovando"; ausência = Off.
struct AccountRenewal: Codable, Equatable {
    enum Mode: String, Codable { case automatic, scheduled }
    var mode: Mode = .automatic
    /// Minutos desde a meia-noite; só relevante em `.scheduled`. nil = usar padrão.
    var anchorMinutes: Int? = nil
    /// Mensagem a disparar; nil = hi mínimo (`AppState.defaultMessage`).
    var messageUID: UUID? = nil
}

@MainActor
final class AppState: ObservableObject {
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

    /// CLI encontrado por provider. Começa true para o ícone de erro não piscar
    /// enquanto a sonda de launch resolve.
    @Published var cliFound: [Provider: Bool] = [.claude: true, .codex: true]

    /// CLIs ausentes que importam: Claude sempre; Codex só quando alguma conta
    /// Codex está em renovação (a Fase 3 soma tarefas Codex habilitadas).
    var missingCLIs: [Provider] {
        Provider.allCases.filter { p in
            guard cliFound[p] == false else { return false }
            if p == .claude { return true }
            return renewals.keys.contains { provider(for: URL(fileURLWithPath: $0)) == .codex }
        }
    }

    /// Mostrar o tempo restante da janela ("3h12") ao lado do ícone da barra.
    @Published var showRemainingInBar: Bool {
        didSet { defaults.set(showRemainingInBar, forKey: Keys.showRemainingInBar) }
    }
    /// Seção selecionada na janela de Configurações (deep-link a partir do menu).
    @Published var settingsSection: SettingsSection = .contas

    static let defaultMessage = Message(
        text: "1+1", kind: .claude,
        uid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)

    /// Hi mínimo Codex — análogo ao defaultMessage, para contas Codex.
    static let defaultCodexMessage = Message(
        text: "1+1", kind: .codex,
        uid: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)

    /// Hi padrão embutido do provider (o "1+1" de cada mundo).
    static func defaultHi(for provider: Provider) -> Message {
        provider == .codex ? defaultCodexMessage : defaultMessage
    }

    @Published var favorites: [Message] {
        didSet { defaults.set(try? JSONEncoder().encode(favorites), forKey: Keys.favorites) }
    }

    /// Diretório de config padrão do Claude Code (`~/.claude`).
    static var defaultConfigDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    /// Diretório de config padrão do Codex (`~/.codex`).
    static var defaultCodexConfigDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    /// Lista exibida na UI: o padrão embutido seguido dos favoritos do usuário.
    var allMessages: [Message] { [Self.defaultMessage, Self.defaultCodexMessage] + favorites }

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

    /// Remove uma conta cadastrada da lista — não toca o disco; limpa a
    /// renovação e o apelido daquele path.
    func unregisterAccount(_ dir: URL) {
        let key = dir.standardizedFileURL.path
        registeredAccounts.removeAll { $0 == key }
        renewals[key] = nil
        aliases[key] = nil
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

    /// Renovação por conta (chave = path padronizado). Presença = renovando.
    @Published var renewals: [String: AccountRenewal] {
        didSet { defaults.set(try? JSONEncoder().encode(renewals), forKey: Keys.renewals) }
    }

    static let defaultAnchorMinutes = 9 * 60

    func renewal(for dir: URL) -> AccountRenewal? { renewals[dir.standardizedFileURL.path] }

    func setRenewal(_ dir: URL, _ config: AccountRenewal?) {
        renewals[dir.standardizedFileURL.path] = config
    }

    /// Mensagem da renovação de uma conta: a fixada (se existir) ou o hi mínimo
    /// do provider da conta.
    func resolvedRenewalMessage(for dir: URL) -> Message {
        if let uid = renewal(for: dir)?.messageUID, let msg = message(withUID: uid) { return msg }
        return Self.defaultHi(for: provider(for: dir))
    }

    /// Cache de sessão do e-mail por conta (evita reler o .claude.json a cada render).
    private var emailCache: [String: String?] = [:]

    /// E-mail logado na conta (oauthAccount.emailAddress), com cache.
    func email(for dir: URL) -> String? {
        let key = dir.standardizedFileURL.path
        if let cached = emailCache[key] { return cached }
        let value = AccountIdentity.email(forConfigDir: dir)
        emailCache[key] = value
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

    /// Cria (ou reaproveita, se idêntica a uma existente) uma mensagem favorita.
    /// Retorna a mensagem resultante com `uid` preenchido, ou nil se o texto for vazio.
    @discardableResult
    func addFavorite(text: String, kind: Message.Kind,
                     model: Message.Model? = nil, effort: Message.Effort? = nil,
                     safeMode: Bool? = nil, configDir: String? = nil,
                     workingDir: String? = nil, showResponse: Bool? = nil) -> Message? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var msg = Message(text: t, kind: kind, model: model, effort: effort,
                          safeMode: safeMode, configDir: configDir,
                          workingDir: workingDir, showResponse: showResponse)
        guard !t.isEmpty else { return nil }
        if msg == Self.defaultMessage { return Self.defaultMessage }
        if msg == Self.defaultCodexMessage { return Self.defaultCodexMessage }
        if let existing = favorites.first(where: { $0 == msg }) { return existing }
        msg.uid = UUID()
        favorites.append(msg)
        return msg
    }

    /// Substitui um favorito por uma versão editada. Preserva a posição na
    /// lista e o uid.
    func updateFavorite(_ old: Message, to new: Message) {
        guard let idx = favorites.firstIndex(of: old) else { return }
        var updated = new
        updated.uid = favorites[idx].uid ?? UUID()
        favorites[idx] = updated
    }

    func removeFavorite(_ msg: Message) {
        favorites.removeAll { $0 == msg }
    }

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

    /// Resolve uma referência estável (uid) para a mensagem atual — default ou favorito.
    func message(withUID uid: UUID) -> Message? {
        if uid == Self.defaultMessage.uid { return Self.defaultMessage }
        if uid == Self.defaultCodexMessage.uid { return Self.defaultCodexMessage }
        return favorites.first { $0.uid == uid }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let paused = "paused"
        static let history = "history"
        static let favorites = "favorites"
        static let showRemainingInBar = "showRemainingInBar"
        static let aliases = "aliases"
        static let renewals = "renewals"
        static let registeredAccounts = "registeredAccounts"
    }

    init(defaults: UserDefaults = .standard,
         home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        self.paused = defaults.bool(forKey: Keys.paused)
        if let data = defaults.data(forKey: Keys.history),
           let decoded = try? JSONDecoder().decode([FireEvent].self, from: data) {
            self.history = decoded
        } else if let data = defaults.data(forKey: "lastEvent"),
                  let event = try? JSONDecoder().decode(FireEvent.self, from: data) {
            self.history = [event] // migração da versão antiga
        } else {
            self.history = []
        }
        self.showRemainingInBar = defaults.bool(forKey: Keys.showRemainingInBar)
        self.favorites = Self.loadFavorites(defaults)
        self.aliases = (defaults.dictionary(forKey: Keys.aliases) as? [String: String]) ?? [:]
        self.renewals = Self.loadRenewals(defaults)
        if let stored = defaults.array(forKey: Keys.registeredAccounts) as? [String] {
            self.registeredAccounts = stored
        } else {
            // Migração única: quem atualizou vindo do scan por convenção mantém as
            // contas extras (ex.: ~/.claude2) sem precisar recadastrar.
            self.registeredAccounts = Self.legacyConventionScan(home: home)
            defaults.set(self.registeredAccounts, forKey: Keys.registeredAccounts)
        }
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
}
