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
                .opacity(state.allScheduledAccountsPaused && !hasProblem ? 0.5 : 1)
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
    private var strings: L10n { state.strings }

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
            Text(strings.noActiveSchedules)
        } else {
            Divider()
            ForEach(scheduledAccounts, id: \.self) { account in
                Text(state.label(for: account))
                Text(statusLine(for: account))
            }
        }
        if let entry = state.nextTaskEntry {
            Divider()
            Text(strings.nextTask(entry.task.name ?? entry.task.resolvedCommand.text,
                                  Fmt.weekdayTime(entry.date, language: state.language)))
        }
        Divider()
        Button(strings.settingsTitle + "...") {
            openWindow(id: "schedule")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button(strings.quit) { NSApplication.shared.terminate(nil) }
        Divider()
        Text("\(strings.version) \(AppVersion.current)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var headerLine: String {
        if let missing = state.missingCLIs.first {
            return strings.installCLIWarning(missing)
        }
        let n = scheduledAccounts.count
        return strings.scheduledAccountsHeader(n)
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
            parts.append(strings.nextHi(Fmt.hhmm(next, language: state.language)))
        } else {
            parts.append(strings.waitingForWindow)
        }
        if let last = lastEvent(for: account) {
            parts.append(strings.lastAt(Fmt.hhmm(last.date, language: state.language), mark(last)))
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
        case .missed: return "◌"
        }
    }
}
