import SwiftUI

/// Formulário de criação/edição de mensagem, em sheet.
struct MessageFormSheet: View {
    @ObservedObject var state: AppState
    /// Mensagem sendo editada; nil = modo "adicionar".
    let editing: Message?
    let onDone: () -> Void

    @State private var text = ""
    @State private var isClaude = true
    @State private var model: Message.Model = Message.defaultModel
    @State private var effort: Message.Effort = Message.defaultEffort
    @State private var safeMode = Message.defaultSafeMode
    @State private var showResponse = false
    @State private var account: String? = nil
    @State private var workingDir = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? "Nova mensagem" : "Editar mensagem").font(.headline)
            TextField("Mensagem ou comando", text: $text)
            Picker("Tipo", selection: $isClaude) {
                Text("Claude").tag(true)
                Text("Comando").tag(false)
            }
            .pickerStyle(.segmented)
            if isClaude {
                ClaudeConfigForm(model: $model, effort: $effort, safeMode: $safeMode,
                                 configDir: $account, workingDir: $workingDir,
                                 accounts: state.discoverAccounts())
            }
            Toggle("Mostrar resposta (histórico + notificação)", isOn: $showResponse)
                .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancelar") { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Adicionar" : "Salvar") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear(perform: load)
    }

    private func load() {
        guard let msg = editing else { return }
        text = msg.text
        isClaude = msg.kind == .claude
        model = msg.resolvedModel
        effort = msg.resolvedEffort
        safeMode = msg.resolvedSafeMode
        showResponse = msg.resolvedShowResponse
        account = msg.configDir
        workingDir = msg.workingDir ?? ""
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let kind: Message.Kind = isClaude ? .claude : .shell
        // Normaliza defaults para nil: modelo enxuto, sem selo desnecessário.
        let msg = Message(
            text: t, kind: kind,
            model: isClaude && model != Message.defaultModel ? model : nil,
            effort: isClaude && effort != Message.defaultEffort ? effort : nil,
            safeMode: isClaude && safeMode != Message.defaultSafeMode ? safeMode : nil,
            configDir: isClaude ? account : nil,
            workingDir: isClaude && !workingDir.isEmpty ? workingDir : nil,
            showResponse: showResponse ? true : nil)
        if let editing {
            state.updateFavorite(editing, to: msg)
        } else {
            state.addFavorite(text: t, kind: kind, model: msg.model, effort: msg.effort,
                              safeMode: msg.safeMode, configDir: msg.configDir,
                              workingDir: msg.workingDir, showResponse: msg.showResponse)
        }
        onDone()
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
