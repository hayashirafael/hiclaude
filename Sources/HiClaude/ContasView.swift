import SwiftUI
import AppKit

/// Seção Contas: informativa — identidade, provedor, pasta local e quantos
/// agendamentos ativos miram cada conta. Renovação e comandos moram em Horários.
struct ContasView: View {
    @ObservedObject var state: AppState
    @State private var editingAlias: URL? = nil
    @State private var aliasDraft = ""
    @State private var invalidFolderAlert = false

    var body: some View {
        Form {
            ForEach(Provider.allCases, id: \.self) { provider in
                let accounts = state.accounts(for: provider)
                ForEach(accounts, id: \.self) { dir in
                    Section {
                        if state.cliFound[provider] == false {
                            Label("CLI do \(provider.displayName) não encontrado — instale para disparar nesta conta",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if !FileManager.default.fileExists(atPath: dir.path) {
                            Label("pasta não encontrada — remova da lista ou restaure a pasta",
                                  systemImage: "questionmark.folder")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        header(dir)
                        LabeledContent("Provedor", value: state.provider(for: dir).displayName)
                        LabeledContent("Pasta") {
                            Text((dir.path as NSString).abbreviatingWithTildeInPath)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                        Text(scheduleCountText(dir)).font(.caption).foregroundStyle(.secondary)
                    } header: {
                        if dir == accounts.first { Text(provider.displayName) }
                    }
                }
            }
            Section {
                Button {
                    addAccount()
                } label: {
                    Label("Adicionar conta…", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Aponte a pasta de config de uma conta (Claude Code ou Codex) — o nome é livre; o tipo é inferido pelo conteúdo. Agendamentos são criados na aba Horários.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Pasta inválida", isPresented: $invalidFolderAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A pasta escolhida não parece uma pasta de config do Claude Code nem do Codex.")
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
        panel.prompt = "Adicionar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if state.registerAccount(url) == nil { invalidFolderAlert = true }
    }

    @ViewBuilder
    private func header(_ dir: URL) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if editingAlias == dir {
                    TextField("Apelido", text: $aliasDraft, onCommit: { commitAlias(dir) })
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(state.label(for: dir))
                }
                if let email = state.email(for: dir), email != state.label(for: dir) {
                    Text(email).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
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
                .help("Remover da lista (não apaga nada do disco; desabilita os agendamentos da conta)")
            }
        }
    }

    private func scheduleCountText(_ dir: URL) -> String {
        switch state.activeScheduleCount(for: dir) {
        case 0: return "nenhum agendamento ativo"
        case 1: return "1 agendamento ativo"
        case let n: return "\(n) agendamentos ativos"
        }
    }

    private func commitAlias(_ dir: URL) {
        state.setAlias(dir, aliasDraft)
        editingAlias = nil
    }
}
