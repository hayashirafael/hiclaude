import Foundation

enum Fmt {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static func hhmm(_ date: Date) -> String { time.string(from: date) }

    static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true // "hoje", "ontem" conforme o locale
        return f
    }()

    static func dayTime(_ date: Date) -> String { dayTimeFormatter.string(from: date) }

    /// Tempo restante compacto para a barra: "3h12".
    static func remaining(until end: Date, from now: Date) -> String {
        let secs = max(0, Int(end.timeIntervalSince(now)))
        return "\(secs / 3600)h" + String(format: "%02d", (secs % 3600) / 60)
    }
}
