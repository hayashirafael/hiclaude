import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case contas, horarios, historico, geral
    var id: String { rawValue }
    func title(language: AppLanguage) -> String {
        L10n(language: language).settingsSectionTitle(self)
    }
    var icon: String {
        switch self {
        case .contas: return "person.crop.circle"
        case .horarios: return "checklist"
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
                Label(section.title(language: state.language), systemImage: section.icon).tag(section)
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
        case .horarios: HorariosView(state: state)
        case .historico: HistoryTab(state: state)
        case .geral: GeneralTab(state: state)
        }
    }
}
