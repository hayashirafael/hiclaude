import Foundation

/// Funções puras da agenda: horários fixos (minutos desde a meia-noite) ×
/// dias da semana (padrão do Calendar: 1 = domingo … 7 = sábado).
enum AgendaMath {
    /// Próxima ocorrência estritamente após `now`. nil se horários ou dias
    /// estiverem vazios.
    static func nextOccurrence(times: [Int], weekdays: Set<Int>, after now: Date,
                               calendar: Calendar) -> Date? {
        guard !times.isEmpty, !weekdays.isEmpty else { return nil }
        for dayOffset in 0...7 { // 8 dias cobrem qualquer combinação de weekdays
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now)
            else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            for minutes in times.sorted() {
                guard let fire = ScheduleMath.date(bySettingMinutes: minutes, ofDay: day,
                                                   calendar: calendar) else { continue }
                if fire > now { return fire } // dias e horários ascendentes → primeiro > now é o mínimo
            }
        }
        return nil
    }

    /// Ocorrência mais recente em (since, now] — o catch-up a executar após
    /// um sleep. Uma só: sleep longo não gera rajada de disparos atrasados.
    static func lastMissedOccurrence(times: [Int], weekdays: Set<Int>, between since: Date,
                                     and now: Date, calendar: Calendar) -> Date? {
        guard since < now else { return nil }
        var best: Date?
        for dayOffset in -7...0 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now)
            else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            for minutes in times {
                guard let fire = ScheduleMath.date(bySettingMinutes: minutes, ofDay: day,
                                                   calendar: calendar) else { continue }
                if fire > since, fire <= now, best == nil || fire > best! {
                    best = fire
                }
            }
        }
        return best
    }
}
