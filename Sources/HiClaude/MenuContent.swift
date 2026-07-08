import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var state: AppState

    var body: some View {
        Image(systemName: name)
    }

    private var name: String {
        if !state.claudeFound || lastEventFailed { return "exclamationmark.bubble" }
        return state.paused ? "bubble.left" : "bubble.left.fill"
    }

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
        if let event = state.lastEvent {
            Text(eventLine(event))
        }
        if let end = state.activeWindowEnd, end > Date() {
            Text("Janela ativa até \(Fmt.hhmm(end))")
        }
        Divider()
        Button("Enviar hi agora") { Task { await env.fireNow() } }
        Button(state.paused ? "Retomar" : "Pausar") { env.togglePause() }
        Divider()
        Button("Horários…") {
            openWindow(id: "schedule")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Sair") { NSApplication.shared.terminate(nil) }
    }

    private var statusLine: String {
        if !state.claudeFound { return "CLI do Claude não encontrado — instale o Claude Code" }
        if state.paused { return "Pausado" }
        if let next = env.nextFireDate { return "Ativo — próximo: \(Fmt.hhmm(next))" }
        return "Ativo — nenhum horário configurado"
    }

    private func eventLine(_ event: FireEvent) -> String {
        let time = Fmt.hhmm(event.date)
        switch event.result {
        case .success:
            return "Último hi: \(time) ✓"
        case .skipped(let until):
            return "Pulado \(time) — janela já ativa até \(Fmt.hhmm(until))"
        case .failure(let message):
            return "Último hi: \(time) ✗ — \(message)"
        }
    }
}
