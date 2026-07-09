import SwiftUI
import AppKit

/// Seção Contas: por conta, identidade + apelido + modo de renovação
/// (Off/Automática/Programada) + âncora + mensagem + status.
struct ContasView: View {
    @ObservedObject var state: AppState
    @State private var editingAlias: URL? = nil
    @State private var aliasDraft = ""
    /// Conta para a qual o sheet "Novo…" foi aberto; nil = fechado.
    @State private var newMessageFor: URL? = nil
    @State private var invalidFolderAlert = false

    /// Tag sentinela do item "Novo…" no picker de comando.
    private static let newCommandSentinel = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

    var body: some View {
        Form {
            ForEach(Provider.allCases, id: \.self) { provider in
                let accounts = state.accounts(for: provider)
                ForEach(accounts, id: \.self) { dir in
                    Section {
                        if state.cliFound[provider] == false {
                            Label("CLI do \(provider.displayName) não encontrado — instale para renovar esta conta",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if !FileManager.default.fileExists(atPath: dir.path) {
                            Label("pasta não encontrada — remova da lista ou restaure a pasta",
                                  systemImage: "questionmark.folder")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        header(dir)
                        modePicker(dir)
                        if state.renewal(for: dir)?.mode == .scheduled {
                            anchorPicker(dir)
                        }
                        if state.renewal(for: dir) != nil {
                            messagePicker(dir)
                            Text(statusText(dir)).font(.caption).foregroundStyle(.secondary)
                        }
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
                Text("Aponte a pasta de config de uma conta (Claude Code ou Codex) — o nome é livre; o tipo é inferido pelo conteúdo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Pasta inválida", isPresented: $invalidFolderAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A pasta escolhida não parece uma pasta de config do Claude Code nem do Codex.")
        }
        .sheet(isPresented: Binding(
            get: { newMessageFor != nil },
            set: { if !$0 { newMessageFor = nil } })) {
            MessageFormSheet(state: state, editing: nil) { created in
                if let created, let dir = newMessageFor {
                    var c = state.renewal(for: dir) ?? AccountRenewal()
                    c.messageUID = created.uid
                    state.setRenewal(dir, c)
                }
                newMessageFor = nil
            }
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
                if !state.accounts(for: .codex).isEmpty {
                    Text(state.provider(for: dir).displayName).font(.caption2).foregroundStyle(.tertiary)
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
                .help("Remover da lista (não apaga nada do disco)")
            }
        }
    }

    private func modePicker(_ dir: URL) -> some View {
        Picker("Renovação", selection: modeBinding(dir)) {
            Text("Off").tag(ModeChoice.off)
            Text("Automática").tag(ModeChoice.automatic)
            Text("Programada").tag(ModeChoice.scheduled)
        }
        .pickerStyle(.segmented)
    }

    private func anchorPicker(_ dir: URL) -> some View {
        DatePicker("Início diário", selection: anchorBinding(dir),
                   displayedComponents: .hourAndMinute)
    }

    private func messagePicker(_ dir: URL) -> some View {
        let provider = state.provider(for: dir)
        return Picker("Comando", selection: messageBinding(dir)) {
            Text(AppState.defaultHi(for: provider).text).tag(UUID?.none)
            ForEach(compatibleFavorites(provider)) { msg in
                Text(msg.text).tag(msg.uid)
            }
            Divider()
            Text("Novo…").tag(UUID?.some(Self.newCommandSentinel))
        }
    }

    /// Favoritos que fazem sentido para renovar uma conta do provider: o kind
    /// do próprio provider (abre a janela) e shell (script do usuário).
    private func compatibleFavorites(_ provider: Provider) -> [Message] {
        state.favorites.filter { msg in
            switch msg.kind {
            case .shell: return true
            case .claude: return provider == .claude
            case .codex: return provider == .codex
            }
        }
    }

    private func statusText(_ dir: URL) -> String {
        if let date = state.nextRenewals[dir.standardizedFileURL] {
            return "renovando · próxima \(Fmt.hhmm(date))"
        }
        return "aguardando janela"
    }

    // MARK: - Bindings

    private enum ModeChoice: Hashable { case off, automatic, scheduled }

    private func modeBinding(_ dir: URL) -> Binding<ModeChoice> {
        Binding(
            get: {
                switch state.renewal(for: dir)?.mode {
                case .some(.automatic): return .automatic
                case .some(.scheduled): return .scheduled
                case .none: return .off
                }
            },
            set: { choice in
                switch choice {
                case .off:
                    state.setRenewal(dir, nil)
                case .automatic:
                    var c = state.renewal(for: dir) ?? AccountRenewal()
                    c.mode = .automatic
                    state.setRenewal(dir, c)
                case .scheduled:
                    var c = state.renewal(for: dir) ?? AccountRenewal()
                    c.mode = .scheduled
                    if c.anchorMinutes == nil { c.anchorMinutes = AppState.defaultAnchorMinutes }
                    state.setRenewal(dir, c)
                }
            })
    }

    private func anchorBinding(_ dir: URL) -> Binding<Date> {
        Binding(
            get: {
                let m = state.renewal(for: dir)?.anchorMinutes ?? AppState.defaultAnchorMinutes
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let p = Calendar.current.dateComponents([.hour, .minute], from: date)
                var c = state.renewal(for: dir) ?? AccountRenewal(mode: .scheduled)
                c.mode = .scheduled
                c.anchorMinutes = (p.hour ?? 0) * 60 + (p.minute ?? 0)
                state.setRenewal(dir, c)
            })
    }

    private func messageBinding(_ dir: URL) -> Binding<UUID?> {
        Binding(
            get: { state.renewal(for: dir)?.messageUID },
            set: { uid in
                guard uid != Self.newCommandSentinel else {
                    newMessageFor = dir
                    return
                }
                var c = state.renewal(for: dir) ?? AccountRenewal()
                c.messageUID = uid
                state.setRenewal(dir, c)
            })
    }

    private func commitAlias(_ dir: URL) {
        state.setAlias(dir, aliasDraft)
        editingAlias = nil
    }
}
