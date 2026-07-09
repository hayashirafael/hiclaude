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
}
