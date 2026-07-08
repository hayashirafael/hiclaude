import SwiftUI

struct GeneralTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                Picker("Conta padrão", selection: accountBinding) {
                    ForEach(state.discoverAccounts(), id: \.self) { dir in
                        Text(dir.lastPathComponent).tag(dir.standardizedFileURL)
                    }
                }
                if LoginItem.isSupported {
                    Toggle("Iniciar com o Mac", isOn: Binding(
                        get: { LoginItem.isEnabled },
                        set: { LoginItem.setEnabled($0) }))
                }
            } footer: {
                Text("Conta Claude padrão (CLAUDE_CONFIG_DIR) — cada mensagem pode sobrescrever.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var accountBinding: Binding<URL> {
        Binding(get: { state.resolvedConfigDir.standardizedFileURL },
                set: { state.setAccount($0) })
    }
}
