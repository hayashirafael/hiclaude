import SwiftUI

struct GeneralTab: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section {
                if LoginItem.isSupported {
                    Toggle("Iniciar com o Mac", isOn: Binding(
                        get: { LoginItem.isEnabled },
                        set: { LoginItem.setEnabled($0) }))
                }
                Toggle("Tempo restante na barra", isOn: $state.showRemainingInBar)
            } footer: {
                Text("O tempo na barra mostra a janela que vence primeiro entre as contas em renovação.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
