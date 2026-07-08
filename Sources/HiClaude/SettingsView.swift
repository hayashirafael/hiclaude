import SwiftUI

enum SettingsTab: Hashable { case schedules, messages, history, general }

/// Janela de configuração em abas, estilo Ajustes do Sistema.
struct SettingsView: View {
    @ObservedObject var state: AppState
    let onChange: () -> Void

    var body: some View {
        TabView(selection: $state.settingsTab) {
            SchedulesTab(state: state, onChange: onChange)
                .tabItem { Label("Horários", systemImage: "clock") }
                .tag(SettingsTab.schedules)
            MessagesTab(state: state)
                .tabItem { Label("Mensagens", systemImage: "bubble.left") }
                .tag(SettingsTab.messages)
            HistoryTab(state: state)
                .tabItem { Label("Histórico", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
            GeneralTab(state: state)
                .tabItem { Label("Geral", systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .frame(width: 440)
    }
}
