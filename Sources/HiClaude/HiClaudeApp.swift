import AppKit
import SwiftUI

@main
struct HiYashiApp: App {
    @StateObject private var env = AppEnvironment()

    /// Vive pelo processo inteiro: o kernel solta o flock quando ele morre.
    private static let instanceLock = SingleInstanceLock()

    init() {
        // Duas instâncias sobre o mesmo UserDefaults = disparos duplicados e
        // histórico sobrescrito. A recém-aberta avisa e sai; o `@StateObject`
        // é preguiçoso, então o AppEnvironment (timers/engines) nem chega a
        // existir neste caminho.
        if !Self.instanceLock.acquire() {
            let language = AppLanguage(
                rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .english
            let strings = L10n(language: language)
            let alert = NSAlert()
            alert.messageText = strings.alreadyRunningTitle
            alert.informativeText = strings.alreadyRunningBody
            alert.runModal()
            exit(0)
        }
        AppPaths.migrateSupportDirectory()
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
            SettingsView(state: env.state, env: env)
        }
        .windowResizability(.contentSize)
    }
}
