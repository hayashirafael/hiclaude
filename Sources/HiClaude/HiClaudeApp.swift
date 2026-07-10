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
        } label: {
            MenuBarLabel(state: env.state)
        }
        .menuBarExtraStyle(.menu)

        Window(env.state.strings.settingsTitle, id: "schedule") {
            SettingsView(state: env.state)
        }
        .windowResizability(.contentSize)
    }
}
