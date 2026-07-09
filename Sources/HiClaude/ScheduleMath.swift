import Foundation

/// Funções puras de agenda. `times` são minutos desde a meia-noite (07:00 → 420).
enum ScheduleMath {
    static func date(bySettingMinutes minutes: Int, ofDay day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    static let renewalWindow: TimeInterval = 5 * 3600
    /// 4 janelas de 5h cobrem 20h; sobra um gap de 4h antes da próxima âncora.
    static let renewalWindowsPerDay = 4

    /// Datas de disparo do ciclo diário ancorado (âncora + k*5h, k in 0..<4),
    /// repetido a cada 24h. Retorna o próximo disparo estritamente após `now`.
    static func nextScheduledRenewal(anchorMinutes: Int, after now: Date,
                                     calendar: Calendar) -> Date? {
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let anchor = date(bySettingMinutes: anchorMinutes, ofDay: day, calendar: calendar)
            else { continue }
            for k in 0..<renewalWindowsPerDay {
                let fire = anchor.addingTimeInterval(Double(k) * renewalWindow)
                if fire > now { return fire } // dias e k ascendentes → primeiro > now é o mínimo
            }
        }
        return nil
    }

    /// Disparo agendado mais recente em (lastCheck, now] cuja janela de 5h ainda
    /// cobre `now` — o hi a executar como catch-up (ex.: perdido no sleep). nil no
    /// gap noturno (nenhuma janela cobre `now`) ou se nada passou.
    static func missedScheduledRenewal(anchorMinutes: Int, between lastCheck: Date,
                                       and now: Date, calendar: Calendar) -> Date? {
        guard lastCheck < now else { return nil }
        var best: Date?
        for dayOffset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let anchor = date(bySettingMinutes: anchorMinutes, ofDay: day, calendar: calendar)
            else { continue }
            for k in 0..<renewalWindowsPerDay {
                let fire = anchor.addingTimeInterval(Double(k) * renewalWindow)
                if fire > lastCheck, fire <= now,
                   fire.addingTimeInterval(renewalWindow) > now,
                   best == nil || fire > best! {
                    best = fire
                }
            }
        }
        return best
    }
}
