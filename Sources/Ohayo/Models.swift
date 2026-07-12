import Foundation

enum FireResult: Codable, Equatable {
    case success
    case skipped(activeUntil: Date)
    case failure(message: String)
    case missed(occurrence: Date)
}

enum FireOrigin: String, Codable { case scheduled, manual, renewal, agenda }

struct FireEvent: Codable, Equatable {
    let date: Date
    let result: FireResult
    var messageText: String? = nil
    var account: String? = nil
    var origin: FireOrigin? = nil
    var response: String? = nil
    var accountPath: String? = nil
    var provider: Provider? = nil
    var modelName: String? = nil
    var aliasSnapshot: String? = nil
    var emailSnapshot: String? = nil
}

struct EventIdentity: Equatable {
    let accountName: String?
    let alias: String?
    let email: String?
    let provider: Provider?
    let modelName: String?

    var displayName: String? { alias ?? email ?? accountName }
}

struct Message: Codable, Identifiable {
    enum Kind: String, Codable { case claude, shell, codex }
    enum CodexReasoning: String, Codable, CaseIterable { case minimal, low, medium, high }
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
    enum Effort: String, Codable, CaseIterable { case low, medium, high, xhigh, max }

    var text: String
    var kind: Kind
    var model: Model? = nil
    var effort: Effort? = nil
    var safeMode: Bool? = nil
    var configDir: String? = nil
    var workingDir: String? = nil
    var uid: UUID? = nil
    var showResponse: Bool? = nil
    var runInTerminal: Bool? = nil
    var notifyOnSuccess: Bool? = nil
    var codexModel: String? = nil
    var codexReasoning: CodexReasoning? = nil
    /// Skill da conta prefixada ao prompt no disparo (`/skill` no Claude,
    /// `$skill` no Codex). nil/vazia = sem skill. Só Claude/Codex.
    var skill: String? = nil

    var id: String { uid?.uuidString ?? contentKey }

    private var contentKey: String {
        let modelValue = model?.rawValue ?? ""
        let effortValue = effort?.rawValue ?? ""
        let safeModeValue = safeMode.map(String.init) ?? ""
        let showResponseValue = showResponse.map(String.init) ?? ""
        let runInTerminalValue = runInTerminal.map(String.init) ?? ""
        let notifyOnSuccessValue = notifyOnSuccess.map(String.init) ?? ""
        let reasoningValue = codexReasoning?.rawValue ?? ""
        let values = [
            kind.rawValue, text, modelValue, effortValue, safeModeValue,
            configDir ?? "", workingDir ?? "", showResponseValue,
            runInTerminalValue, notifyOnSuccessValue, codexModel ?? "", reasoningValue,
            skill ?? ""
        ]
        return values.joined(separator: "\u{1}")
    }
}

extension Message: Equatable {
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.text == rhs.text && lhs.kind == rhs.kind && lhs.model == rhs.model
            && lhs.effort == rhs.effort && lhs.safeMode == rhs.safeMode
            && lhs.configDir == rhs.configDir && lhs.workingDir == rhs.workingDir
            && lhs.showResponse == rhs.showResponse
            && lhs.runInTerminal == rhs.runInTerminal
            && lhs.notifyOnSuccess == rhs.notifyOnSuccess
            && lhs.codexModel == rhs.codexModel && lhs.codexReasoning == rhs.codexReasoning
            && lhs.skill == rhs.skill
    }
}

extension Message {
    static let defaultModel: Model = .haiku
    static let defaultEffort: Effort = .low
    static let defaultSafeMode = true
    var resolvedModel: Model { model ?? Self.defaultModel }
    var resolvedEffort: Effort { effort ?? Self.defaultEffort }
    /// Skill efetiva: nil e string vazia contam como "sem skill".
    var hasSkill: Bool { skill?.isEmpty == false && kind != .shell }
    var resolvedSafeMode: Bool {
        // Skill exige safe-mode desligado: `--safe-mode` faz o CLI pular
        // skills — um estado contraditório persistido não pode gerar disparo
        // que ignora a skill em silêncio.
        hasSkill ? false : (safeMode ?? Self.defaultSafeMode)
    }
    /// Prompt final enviado ao CLI: skill prefixada na sintaxe nativa do
    /// provider (`/skill` no Claude, `$skill` no Codex); shell ignora skill.
    var resolvedPromptText: String {
        guard hasSkill, let skill else { return text }
        return kind == .codex ? "$\(skill) \(text)" : "/\(skill) \(text)"
    }
    var resolvedShowResponse: Bool { showResponse ?? false }
    var resolvedNotifyOnSuccess: Bool { notifyOnSuccess ?? false }
    var resolvedRunInTerminal: Bool {
        switch kind {
        case .claude, .codex: return runInTerminal ?? true
        case .shell: return false
        }
    }
}

struct ScheduledTask: Identifiable, Equatable {
    enum Repetition: String, Codable { case continuous, fixed }

    var uid: UUID
    var name: String? = nil
    var command: Message? = nil
    var repetition: Repetition = .fixed
    var times: [Int] = []
    var weekdays: Set<Int> = []
    var enabled: Bool = true

    var id: UUID { uid }
    var resolvedCommand: Message { command ?? AppState.defaultMessage }
}

/// Decodificação lossy de arrays: um elemento ilegível vira `nil` em vez de
/// derrubar o array inteiro. Protege o blob persistido de `tasks`/`history`
/// contra um único item com raw value desconhecido (downgrade para uma build
/// mais antiga) que apagaria toda a lista.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension ScheduledTask: Codable {
    private enum CodingKeys: String, CodingKey {
        case uid, name, command, repetition, times, weekdays, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(UUID.self, forKey: .uid)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        command = try c.decodeIfPresent(Message.self, forKey: .command)
        repetition = try c.decodeIfPresent(Repetition.self, forKey: .repetition) ?? .fixed
        times = try c.decodeIfPresent([Int].self, forKey: .times) ?? []
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}
