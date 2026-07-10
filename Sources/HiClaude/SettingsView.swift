import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case contas, comandos, historico, geral
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contas: return "Contas"
        case .comandos: return "Comandos"
        case .historico: return "Histórico"
        case .geral: return "Geral"
        }
    }
    var icon: String {
        switch self {
        case .contas: return "person.crop.circle"
        case .comandos: return "terminal"
        case .historico: return "clock.arrow.circlepath"
        case .geral: return "gearshape"
        }
    }
}

/// Janela de configuração em sidebar, estilo Ajustes do Sistema.
struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $state.settingsSection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 480)
    }

    @ViewBuilder
    private var detail: some View {
        switch state.settingsSection {
        case .contas: ContasView(state: state)
        case .comandos: MessagesTab(state: state)
        case .historico: HistoryTab(state: state)
        case .geral: GeneralTab(state: state)
        }
    }
}
