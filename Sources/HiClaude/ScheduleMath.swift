import Foundation

/// Funções puras de agenda. `times` são minutos desde a meia-noite (07:00 → 420).
enum ScheduleMath {
    static func date(bySettingMinutes minutes: Int, ofDay day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    /// Próxima ocorrência futura (hoje ou amanhã) entre os horários dados.
    static func nextFireDate(times: [Int], after now: Date, calendar: Calendar) -> Date? {
        guard !times.isEmpty else { return nil }
        var candidates: [Date] = []
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            for minutes in times {
                if let d = date(bySettingMinutes: minutes, ofDay: day, calendar: calendar), d > now {
                    candidates.append(d)
                }
            }
        }
        return candidates.min()
    }

    /// Algum horário agendado caiu em (lastCheck, now]?
    static func hasMissedTime(times: [Int], between lastCheck: Date, and now: Date, calendar: Calendar) -> Bool {
        guard !times.isEmpty, lastCheck < now else { return false }
        var day = calendar.startOfDay(for: lastCheck)
        let endDay = calendar.startOfDay(for: now)
        while day <= endDay {
            for minutes in times {
                if let d = date(bySettingMinutes: minutes, ofDay: day, calendar: calendar),
                   d > lastCheck, d <= now {
                    return true
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return false
    }
}
