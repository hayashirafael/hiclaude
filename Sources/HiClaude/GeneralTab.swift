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
                Toggle("Tempo restante na barra", isOn: $state.showRemainingInBar)
            } footer: {
                Text("Conta Claude padrão (CLAUDE_CONFIG_DIR) — cada mensagem pode sobrescrever.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(state.discoverAccounts(), id: \.self) { dir in
                    HStack {
                        Toggle(dir.lastPathComponent, isOn: Binding(
                            get: { state.isRenewOn(dir) },
                            set: { state.setRenew(dir, enabled: $0) }))
                        Spacer()
                        Text(renewStatus(dir))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Renovação automática")
            } footer: {
                Text("Ao fim da janela de 5h, envia um hi e abre a próxima — mantém a conta sempre com janela ativa. Pausar suspende as renovações.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var accountBinding: Binding<URL> {
        Binding(get: { state.resolvedConfigDir.standardizedFileURL },
                set: { state.setAccount($0) })
    }

    private func renewStatus(_ dir: URL) -> String {
        guard state.isRenewOn(dir) else { return "desligado" }
        if let date = state.nextRenewals[dir.standardizedFileURL] {
            return "renovando · próxima \(Fmt.hhmm(date))"
        }
        return "aguardando janela"
    }
}
