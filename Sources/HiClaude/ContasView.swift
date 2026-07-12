import SwiftUI
import AppKit

/// Seção Contas: informativa — identidade, provedor, pasta local e quantos
/// agendamentos ativos miram cada conta. Renovação e comandos moram em Horários.
struct ContasView: View {
    @ObservedObject var state: AppState
    @State private var editingAlias: URL? = nil
    @State private var aliasDraft = ""
    @State private var invalidFolderAlert = false
    private var strings: L10n { state.strings }

    var body: some View {
        Form {
            ForEach(Provider.allCases, id: \.self) { provider in
                let accounts = state.accounts(for: provider)
                ForEach(accounts, id: \.self) { dir in
                    Section {
                        if state.cliFound[provider] == false {
                            Label(strings.installCLIForAccount(provider),
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if !FileManager.default.fileExists(atPath: dir.path) {
                            Label(strings.accountFolderMissingAccountTab,
                                  systemImage: "questionmark.folder")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        header(dir)
                        LabeledContent(strings.providerLabel, value: state.provider(for: dir).displayName)
                        LabeledContent(strings.folderLabel) {
                            Text((dir.path as NSString).abbreviatingWithTildeInPath)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                        Text(scheduleCountText(dir)).font(.caption).foregroundStyle(.secondary)
                    } header: {
                        if dir == accounts.first {
                            HStack(spacing: 6) {
                                ProviderIcon(provider: provider, size: 14)
                                Text(provider.displayName)
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    addAccount()
                } label: {
                    Label(strings.addAccount, systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            } footer: {
                Text(strings.accountsFooter)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(strings.invalidFolderTitle, isPresented: $invalidFolderAlert) {
            Button(strings.ok, role: .cancel) {}
        } message: {
            Text(strings.invalidFolderMessage)
        }
    }

    /// Abre o NSOpenPanel para cadastrar uma conta; pasta sem assinatura → alerta.
    private func addAccount() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true // ~/.claude2 e afins são pastas ocultas
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = strings.add
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if state.registerAccount(url) == nil { invalidFolderAlert = true }
    }

    @ViewBuilder
    private func header(_ dir: URL) -> some View {
        HStack(spacing: 9) {
            ProviderIcon(provider: state.provider(for: dir), size: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                if editingAlias == dir {
                    TextField(strings.accountAlias, text: $aliasDraft, onCommit: { commitAlias(dir) })
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(state.label(for: dir))
                }
                if let email = state.email(for: dir), email != state.label(for: dir) {
                    Text(email).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.isPaused(dir) {
                Text(strings.pausedBadge)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            }
            Button {
                state.setPaused(dir, !state.isPaused(dir))
            } label: {
                Image(systemName: state.isPaused(dir) ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.plain)
            .help(state.isPaused(dir) ? strings.resumeAccount : strings.pauseAccount)
            Button {
                if editingAlias == dir { commitAlias(dir) }
                else { editingAlias = dir; aliasDraft = state.alias(for: dir) ?? "" }
            } label: {
                Image(systemName: editingAlias == dir ? "checkmark" : "pencil")
            }
            .buttonStyle(.plain)
            if state.registeredAccounts.contains(dir.standardizedFileURL.path) {
                Button { state.unregisterAccount(dir) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .help(strings.removeAccountHelp)
            }
        }
    }

    private func scheduleCountText(_ dir: URL) -> String {
        strings.activeScheduleCount(state.activeScheduleCount(for: dir))
    }

    private func commitAlias(_ dir: URL) {
        state.setAlias(dir, aliasDraft)
        editingAlias = nil
    }
}
