import Foundation

enum Fmt {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static func hhmm(_ date: Date) -> String { time.string(from: date) }
}
