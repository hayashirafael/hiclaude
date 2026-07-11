import Foundation

/// Lógica pura do painel do menu — testável sem UI. As dependências de
/// AppState entram como closures/dicionários para os testes não tocarem disco.
enum MenuPanelLogic {
    /// Contas com pelo menos um agendamento habilitado, sem duplicatas,
    /// ordenadas pelo rótulo (mesma regra do menu antigo).
    static func scheduledAccounts(tasks: [ScheduledTask],
                                  accountDir: (ScheduledTask) -> URL?,
                                  label: (URL) -> String) -> [URL] {
        let dirs = Set(tasks.filter { $0.enabled }.compactMap { accountDir($0) })
        return dirs.sorted {
            label($0).localizedCaseInsensitiveCompare(label($1)) == .orderedAscending
        }
    }

    /// Nome de exibição de um agendamento no painel: nome explícito → texto do
    /// comando truncado; contínuo sem nome vira o fallback ("renovação").
    static func eventName(_ task: ScheduledTask, renewalFallbackName: String) -> String {
        if let name = task.name, !name.isEmpty { return name }
        if task.repetition == .continuous { return renewalFallbackName }
        let text = task.resolvedCommand.text
        return text.count > 30 ? String(text.prefix(30)) + "…" : text
    }

    /// Próximo evento da conta: o disparo futuro mais próximo entre o
    /// contínuo (nextRenewals) e os fixos (nextTaskFires) que a miram.
    static func nextEvent(for account: URL, tasks: [ScheduledTask],
                          nextRenewals: [URL: Date], nextTaskFires: [UUID: Date],
                          accountDir: (ScheduledTask) -> URL?, now: Date,
                          renewalFallbackName: String) -> (name: String, date: Date)? {
        var candidates: [(name: String, date: Date)] = []
        for task in tasks where task.enabled && accountDir(task) == account {
            let date: Date?
            switch task.repetition {
            case .continuous: date = nextRenewals[account]
            case .fixed: date = nextTaskFires[task.uid]
            }
            if let date, date > now {
                candidates.append((eventName(task, renewalFallbackName: renewalFallbackName), date))
            }
        }
        return candidates.min { $0.date < $1.date }
    }
}
