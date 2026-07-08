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
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.times = (defaults.array(forKey: Keys.times) as? [Int]) ?? [7 * 60]
        self.paused = defaults.bool(forKey: Keys.paused)
        if let data = defaults.data(forKey: Keys.lastEvent) {
            self.lastEvent = try? JSONDecoder().decode(FireEvent.self, from: data)
        }
    }
}
