import SwiftUI

@main
struct HiClaudeApp: App {
    @StateObject private var env = AppEnvironment()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: env.state, env: env)
                .onAppear { Task { await env.refreshWindowStatus() } }
        } label: {
            MenuBarIcon(state: env.state)
        }
        .menuBarExtraStyle(.menu)

        Window("Horários", id: "schedule") {
            Text("Configuração de horários (Task 9)")
                .padding()
        }
        .windowResizability(.contentSize)
    }
}
