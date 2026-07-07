import SwiftUI

@main
struct HiClaudeApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("HiClaude", systemImage: "bubble.left.fill") {
            Text("HiClaude")
            Button("Sair") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
