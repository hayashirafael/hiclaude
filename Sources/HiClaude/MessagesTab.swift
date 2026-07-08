import SwiftUI

struct MessagesTab: View {
    @ObservedObject var state: AppState
    @State private var newMessage = ""
    @State private var newIsClaude = true
    // Config Claude do formulário (add/editar).
    @State private var newModel: Message.Model = Message.defaultModel
    @State private var newEffort: Message.Effort = Message.defaultEffort
    @State private var newSafe = Message.defaultSafeMode
    @State private var newAccount: String? = nil   // nil = conta global
    @State private var newWorkingDir = ""
    /// Mensagem sendo editada; nil = modo "adicionar".
    @State private var editing: Message? = nil

    var body: some View {
        Form {
            Section {
                ForEach(state.allMessages) { msg in
                    HStack(alignment: .top) {
                        Button {
                            state.setActiveMessage(msg)
                        } label: {
                            Image(systemName: msg == state.resolvedMessage
                                  ? "largecircle.fill.circle" : "circle")
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(msg.text)
                            if msg.kind == .shell {
                                Text("comando")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else if let badge = configBadge(msg) {
                                Text(badge)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()

                        if msg != AppState.defaultMessage {
                            if msg.kind == .claude {
                                Button {
                                    beginEdit(msg)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                if editing == msg { resetForm() }
                                state.removeFavorite(msg)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField(editing == nil ? "Nova mensagem" : "Editar mensagem",
                                  text: $newMessage)
                        Toggle("Claude", isOn: $newIsClaude)
                            .toggleStyle(.checkbox)
                    }
                    if newIsClaude {
                        ClaudeConfigForm(model: $newModel, effort: $newEffort,
                                         safeMode: $newSafe, configDir: $newAccount,
                                         workingDir: $newWorkingDir,
                                         accounts: state.discoverAccounts())
                    }
                    HStack {
                        Button(editing == nil ? "Adicionar" : "Salvar") { commitMessage() }
                        if editing != nil {
                            Button("Cancelar") { resetForm() }
                        }
                    }
                }
            } footer: {
                Text("Com Claude: abre a janela de 5h. Sem Claude: roda o texto como comando.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Resumo compacto da config não-default de uma mensagem Claude (ex:
    /// "Opus 4.8 · high · conta2"). Retorna nil quando tudo está no default.
    private func configBadge(_ msg: Message) -> String? {
        var parts: [String] = []
        if msg.model != nil { parts.append(msg.resolvedModel.label) }
        if msg.effort != nil { parts.append(msg.resolvedEffort.rawValue) }
        if msg.safeMode == false { parts.append("sem safe") }
        if let c = msg.configDir, !c.isEmpty { parts.append(URL(fileURLWithPath: c).lastPathComponent) }
        if let w = msg.workingDir, !w.isEmpty { parts.append(URL(fileURLWithPath: w).lastPathComponent) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func beginEdit(_ msg: Message) {
        editing = msg
        newMessage = msg.text
        newIsClaude = msg.kind == .claude
        newModel = msg.resolvedModel
        newEffort = msg.resolvedEffort
        newSafe = msg.resolvedSafeMode
        newAccount = msg.configDir
        newWorkingDir = msg.workingDir ?? ""
    }

    private func resetForm() {
        editing = nil
        newMessage = ""
        newIsClaude = true
        newModel = Message.defaultModel
        newEffort = Message.defaultEffort
        newSafe = Message.defaultSafeMode
        newAccount = nil
        newWorkingDir = ""
    }

    private func commitMessage() {
        let text = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let kind: Message.Kind = newIsClaude ? .claude : .shell
        // Normaliza valores default para nil: mantém o modelo enxuto e evita
        // exibir selo em mensagens que estão inteiramente no default.
        let model: Message.Model? = newIsClaude && newModel != Message.defaultModel ? newModel : nil
        let effort: Message.Effort? = newIsClaude && newEffort != Message.defaultEffort ? newEffort : nil
        let safe: Bool? = newIsClaude && newSafe != Message.defaultSafeMode ? newSafe : nil
        let account: String? = newIsClaude ? newAccount : nil
        let wd: String? = (newIsClaude && !newWorkingDir.isEmpty) ? newWorkingDir : nil
        let msg = Message(text: text, kind: kind, model: model, effort: effort,
                          safeMode: safe, configDir: account, workingDir: wd)
        if let editing {
            state.updateFavorite(editing, to: msg)
        } else {
            state.addFavorite(text: text, kind: kind, model: model, effort: effort,
                              safeMode: safe, configDir: account, workingDir: wd)
        }
        resetForm()
    }
}

/// Bloco de configuração de uma mensagem Claude (modelo/effort/safe/conta/dir).
/// Exibido no formulário quando o toggle "Claude" está ligado.
struct ClaudeConfigForm: View {
    @Binding var model: Message.Model
    @Binding var effort: Message.Effort
    @Binding var safeMode: Bool
    @Binding var configDir: String?   // nil = conta global
    @Binding var workingDir: String
    let accounts: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Modelo", selection: $model) {
                ForEach(Message.Model.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            Picker("Effort", selection: $effort) {
                ForEach(Message.Effort.allCases, id: \.self) { e in
                    Text(e.rawValue).tag(e)
                }
            }
            Toggle("Safe mode", isOn: $safeMode)
                .toggleStyle(.checkbox)
            Picker("Conta", selection: $configDir) {
                Text("Padrão (global)").tag(String?.none)
                ForEach(accounts, id: \.self) { dir in
                    Text(dir.lastPathComponent).tag(String?.some(dir.path))
                }
            }
            TextField("Diretório (~ por padrão)", text: $workingDir)
        }
        .font(.caption)
    }
}
