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

    /// Contas em renovação, ordenadas por rótulo.
    private var renewingAccounts: [URL] {
        state.renewals.keys
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .sorted { state.label(for: $0).localizedCaseInsensitiveCompare(state.label(for: $1)) == .orderedAscending }
    }

    var body: some View {
        Text(headerLine)
        if renewingAccounts.isEmpty {
            Text("Nenhuma conta em renovação")
        } else {
            Divider()
            ForEach(renewingAccounts, id: \.self) { account in
                Text(state.label(for: account))
                Text(statusLine(for: account))
            }
        }
        if let entry = state.nextTaskEntry {
            Divider()
            Text("Próxima tarefa: \(entry.task.name ?? state.resolvedTaskMessage(for: entry.task).text) · \(Fmt.weekdayTime(entry.date))")
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
        let n = renewingAccounts.count
        return n == 1 ? "1 conta em renovação" : "\(n) contas em renovação"
    }

    private func statusLine(for account: URL) -> String {
        let mode = state.renewal(for: account)?.mode == .scheduled ? "programada" : "automática"
        var parts = [mode]
        let temCodex = renewingAccounts.contains { state.provider(for: $0) == .codex }
        if temCodex { parts.insert(state.provider(for: account).displayName, at: 0) }
        if let next = state.nextRenewals[account.standardizedFileURL], next > Date() {
            parts.append("renova \(Fmt.hhmm(next))")
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
