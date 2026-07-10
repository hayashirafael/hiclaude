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

    /// "qua 08:00" — dia da semana curto + hora, para próximas execuções.
    static let weekdayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        return f
    }()

    static func weekdayTime(_ date: Date) -> String {
        weekdayTimeFormatter.string(from: date)
    }

    /// Minutos desde a meia-noite → "08:00".
    static func minutes(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
