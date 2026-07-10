import Foundation

enum Fmt {
    private static func formatter(language: AppLanguage, configure: (DateFormatter) -> Void) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: language.localeIdentifier)
        configure(f)
        return f
    }

    static func hhmm(_ date: Date, language: AppLanguage = .english) -> String {
        formatter(language: language) {
            $0.dateStyle = .none
            $0.timeStyle = .short
        }.string(from: date)
    }

    static func dayTime(_ date: Date, language: AppLanguage = .english) -> String {
        formatter(language: language) {
            $0.dateStyle = .short
            $0.timeStyle = .short
            $0.doesRelativeDateFormatting = true
        }.string(from: date)
    }

    /// Tempo restante compacto para a barra: "3h12".
    static func remaining(until end: Date, from now: Date) -> String {
        let secs = max(0, Int(end.timeIntervalSince(now)))
        return "\(secs / 3600)h" + String(format: "%02d", (secs % 3600) / 60)
    }

    /// "qua 08:00" — dia da semana curto + hora, para próximas execuções.
    static func weekdayTime(_ date: Date, language: AppLanguage = .english) -> String {
        formatter(language: language) {
            $0.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        }.string(from: date)
    }

    /// Minutos desde a meia-noite → "08:00".
    static func minutes(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
