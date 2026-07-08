import Foundation

/// Funções puras de agenda. `times` são minutos desde a meia-noite (07:00 → 420).
enum ScheduleMath {
    static func date(bySettingMinutes minutes: Int, ofDay day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    /// Próxima ocorrência futura + o horário (minutos) correspondente.
    static func nextFire(times: [Int], after now: Date,
                         calendar: Calendar) -> (date: Date, minutes: Int)? {
        guard !times.isEmpty else { return nil }
        var best: (date: Date, minutes: Int)?
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            for minutes in times {
                if let d = date(bySettingMinutes: minutes, ofDay: day, calendar: calendar),
                   d > now, best == nil || d < best!.date {
                    best = (d, minutes)
                }
            }
        }
        return best
    }

    /// Próxima ocorrência futura (hoje ou amanhã) entre os horários dados.
    static func nextFireDate(times: [Int], after now: Date, calendar: Calendar) -> Date? {
        nextFire(times: times, after: now, calendar: calendar)?.date
    }

    /// Minutos do horário perdido mais recente em (lastCheck, now], se houver.
    static func lastMissedMinutes(times: [Int], between lastCheck: Date, and now: Date,
                                  calendar: Calendar) -> Int? {
        guard !times.isEmpty, lastCheck < now else { return nil }
        var best: (date: Date, minutes: Int)?
        var day = calendar.startOfDay(for: lastCheck)
        let endDay = calendar.startOfDay(for: now)
        while day <= endDay {
            for minutes in times {
                if let d = date(bySettingMinutes: minutes, ofDay: day, calendar: calendar),
                   d > lastCheck, d <= now, best == nil || d > best!.date {
                    best = (d, minutes)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return best?.minutes
    }

    /// Algum horário agendado caiu em (lastCheck, now]?
    static func hasMissedTime(times: [Int], between lastCheck: Date, and now: Date,
                              calendar: Calendar) -> Bool {
        lastMissedMinutes(times: times, between: lastCheck, and: now, calendar: calendar) != nil
    }
}
