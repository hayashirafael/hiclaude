import SwiftUI

/// Label da barra: glifo próprio (balão + arco de renovação) preenchido quando
/// qualquer conta está com janela ativa; exclamação em erro; esmaecido quando
/// pausado. Texto opcional = janela que vence primeiro entre as contas em
/// renovação.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyph.image(for: glyphState))
                .opacity(state.paused && !hasProblem ? 0.5 : 1)
            if state.showRemainingInBar, let end = soonestEnd {
                Text(Fmt.remaining(until: end, from: Date()))
            }
        }
    }

    private var soonestEnd: Date? {
        state.nextRenewals.values.filter { $0 > Date() }.min()
    }

    private var glyphState: MenuBarGlyph.State {
        .init(hasProblem: hasProblem, hasActiveWindow: soonestEnd != nil)
    }

    private var hasProblem: Bool { !state.missingCLIs.isEmpty || lastEventFailed }

    private var lastEventFailed: Bool {
        if case .failure = state.lastEvent?.result { return true }
        return false
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState
    let env: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    /// Contas com pelo menos um agendamento habilitado (Claude/Codex).
    private var scheduledAccounts: [URL] {
        let dirs = Set(state.tasks.filter { $0.enabled }
            .compactMap { state.accountDir(for: $0) })
        return dirs.sorted {
            state.label(for: $0).localizedCaseInsensitiveCompare(state.label(for: $1)) == .orderedAscending
        }
    }

    var body: some View {
        Text(headerLine)
        if scheduledAccounts.isEmpty {
            Text("Nenhum agendamento ativo")
        } else {
            Divider()
            ForEach(scheduledAccounts, id: \.self) { account in
                Text(state.label(for: account))
                Text(statusLine(for: account))
            }
        }
        if let entry = state.nextTaskEntry {
            Divider()
            Text("Próxima tarefa: \(entry.task.name ?? entry.task.resolvedCommand.text) · \(Fmt.weekdayTime(entry.date))")
        }
        Divider()
        Button(state.paused ? "Retomar" : "Pausar") { env.togglePause() }
        Button("Configurações…") {
            openWindow(id: "schedule")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Sair") { NSApplication.shared.terminate(nil) }
    }

    private var headerLine: String {
        if let missing = state.missingCLIs.first {
            let instale = missing == .claude ? "Claude Code" : "Codex CLI"
            return "CLI do \(missing.displayName) não encontrado — instale o \(instale)"
        }
        if state.paused { return "Pausado" }
        let n = scheduledAccounts.count
        if n == 0 { return "Nenhum agendamento ativo" }
        return n == 1 ? "1 conta com agendamentos" : "\(n) contas com agendamentos"
    }

    /// Próximo disparo entre os agendamentos que miram a conta: contínuos vêm
    /// do RenewalEngine (nextRenewals), fixos do TaskScheduler (nextTaskFires).
    private func nextFire(for account: URL) -> Date? {
        var candidates: [Date] = []
        if let d = state.nextRenewals[account], d > Date() { candidates.append(d) }
        for task in state.tasks where task.enabled && task.repetition == .fixed {
            if state.accountDir(for: task) == account,
               let d = state.nextTaskFires[task.uid], d > Date() {
                candidates.append(d)
            }
        }
        return candidates.min()
    }

    private func statusLine(for account: URL) -> String {
        var parts: [String] = []
        let temCodex = scheduledAccounts.contains { state.provider(for: $0) == .codex }
        if temCodex { parts.append(state.provider(for: account).displayName) }
        if let next = nextFire(for: account) {
            parts.append("próximo hi \(Fmt.hhmm(next))")
        } else {
            parts.append("aguardando janela")
        }
        if let last = lastEvent(for: account) {
            parts.append("último \(Fmt.hhmm(last.date)) \(mark(last))")
        }
        return "  " + parts.joined(separator: " · ")
    }

    private func lastEvent(for account: URL) -> FireEvent? {
        let name = account.lastPathComponent
        return state.history.first { $0.account == name }
    }

    private func mark(_ event: FireEvent) -> String {
        switch event.result {
        case .success: return "✓"
        case .skipped: return "↩"
        case .failure: return "✗"
        }
    }
}
