import SwiftUI

/// Label da barra: o ícone reflete a janela de 5h (preenchido = ativa),
/// exclamação = erro, esmaecido = pausado; texto opcional com o restante.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .opacity(state.paused && !hasProblem ? 0.5 : 1)
            if state.showRemainingInBar, let end = state.activeWindowEnd, end > Date() {
                Text(Fmt.remaining(until: end, from: Date()))
            }
        }
    }

    private var symbol: String {
        if hasProblem { return "exclamationmark.bubble" }
        if let end = state.activeWindowEnd, end > Date() { return "bubble.left.fill" }
        return "bubble.left"
    }

    private var hasProblem: Bool { !state.claudeFound || lastEventFailed }

    private var lastEventFailed: Bool {
        if case .failure = state.lastEvent?.result { return true }
        return false
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState
    let env: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)
        if let end = state.activeWindowEnd, end > Date() {
            Text("Janela ativa até \(Fmt.hhmm(end)) (\(Fmt.remaining(until: end, from: Date())))")
        }
        ForEach(state.nextRenewals.sorted(by: { $0.value < $1.value }), id: \.key) { account, date in
            Text("↻ Renova às \(Fmt.hhmm(date)) (\(account.lastPathComponent))")
        }
        if let event = state.lastEvent {
            if event.response != nil {
                Button(eventLine(event)) {
                    state.settingsTab = .history
                    openWindow(id: "schedule")
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else {
                Text(eventLine(event))
            }
        }
        Text("Conta: \(state.resolvedConfigDir.lastPathComponent)")
        Divider()
        Button("Enviar hi agora") { Task { await env.fireNow() } }
        Button(state.paused ? "Retomar" : "Pausar") { env.togglePause() }
        Menu("Mensagem") {
            ForEach(state.allMessages) { msg in
                Button {
                    env.setActiveMessage(msg)
                } label: {
                    let label = msg.kind == .shell ? "\(msg.text) (comando)" : msg.text
                    if msg == state.resolvedMessage {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
            Divider()
            Button("Gerenciar…") {
                state.settingsTab = .messages
                openWindow(id: "schedule")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        Divider()
        Button("Configurações…") {
            openWindow(id: "schedule")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Sair") { NSApplication.shared.terminate(nil) }
    }

    private var statusLine: String {
        if !state.claudeFound { return "CLI do Claude não encontrado — instale o Claude Code" }
        if state.paused { return "Pausado" }
        if let next = env.nextFire {
            let text = state.resolvedMessage(forMinutes: next.minutes).text
            let short = text.count > 24 ? String(text.prefix(24)) + "…" : text
            return "Ativo — próximo: \(Fmt.hhmm(next.date)) · \(short)"
        }
        return "Ativo — nenhum horário configurado"
    }

    private func eventLine(_ event: FireEvent) -> String {
        let time = Fmt.hhmm(event.date)
        switch event.result {
        case .success:
            return event.response != nil ? "Último hi: \(time) ✓ — ver resposta" : "Último hi: \(time) ✓"
        case .skipped(let until):
            return "Pulado \(time) — janela já ativa até \(Fmt.hhmm(until))"
        case .failure(let message):
            return "Último hi: \(time) ✗ — \(message)"
        }
    }
}
