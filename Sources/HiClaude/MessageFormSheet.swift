import SwiftUI

/// Formulário de criação/edição de mensagem, em sheet.
struct MessageFormSheet: View {
    @ObservedObject var state: AppState
    /// Mensagem sendo editada; nil = modo "adicionar".
    let editing: Message?
    /// Chamado ao fechar: nil se cancelado, a mensagem criada/editada se salvo.
    let onDone: (Message?) -> Void

    @State private var text = ""
    @State private var kind: Message.Kind = .claude
    @State private var model: Message.Model = Message.defaultModel
    @State private var effort: Message.Effort = Message.defaultEffort
    @State private var safeMode = Message.defaultSafeMode
    @State private var codexModel = ""
    @State private var codexReasoning: Message.CodexReasoning = .low
    @State private var showResponse = false
    @State private var account: String? = nil
    @State private var workingDir = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? "Novo comando" : "Editar comando").font(.headline)
            TextField("Mensagem ou comando", text: $text)
            Picker("Tipo", selection: $kind) {
                Text("Claude").tag(Message.Kind.claude)
                Text("Codex").tag(Message.Kind.codex)
                Text("Comando").tag(Message.Kind.shell)
            }
            .pickerStyle(.segmented)
            if kind == .claude {
                ClaudeConfigForm(model: $model, effort: $effort, safeMode: $safeMode,
                                 configDir: $account, workingDir: $workingDir,
                                 accounts: state.accounts(for: .claude),
                                 accountLabel: { state.label(for: $0) })
            }
            if kind == .codex {
                CodexConfigForm(model: $codexModel, reasoning: $codexReasoning,
                                configDir: $account, workingDir: $workingDir,
                                accounts: state.accounts(for: .codex),
                                accountLabel: { state.label(for: $0) })
            }
            Toggle("Mostrar resposta (histórico + notificação)", isOn: $showResponse)
                .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancelar") { onDone(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Adicionar" : "Salvar") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear(perform: load)
        // Conta é por provider (~/.claude* vs ~/.codex*); trocar o Tipo sem
        // limpar a conta persistiria um configDir do provider errado (hi na
        // conta errada — ex.: `codex exec` com CODEX_HOME de pasta Claude).
        // O reset é CONDICIONAL: o load() de um favorito não-Claude também
        // dispara este onChange (kind inicia .claude e o load o troca DEPOIS
        // de setar `account`), e um reset incondicional apagaria a conta
        // salva ao simplesmente abrir "Editar". Se a conta já é válida para
        // o novo kind, não há nada para limpar.
        .onChange(of: kind) { newKind in
            guard let current = account else { return }
            let valid: Bool
            switch newKind {
            case .claude: valid = state.accounts(for: .claude).contains { $0.path == current }
            case .codex: valid = state.accounts(for: .codex).contains { $0.path == current }
            case .shell: valid = false
            }
            if !valid { account = nil }
        }
    }

    private func load() {
        guard let msg = editing else { return }
        text = msg.text
        kind = msg.kind
        model = msg.resolvedModel
        effort = msg.resolvedEffort
        safeMode = msg.resolvedSafeMode
        codexModel = msg.codexModel ?? ""
        codexReasoning = msg.codexReasoning ?? .low
        showResponse = msg.resolvedShowResponse
        account = msg.configDir
        workingDir = msg.workingDir ?? ""
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // Segunda barreira além do onChange(of: kind): se `account` ainda
        // apontar para uma conta de outro provider (ex.: caminho que não
        // passou pela troca de Tipo), descarta — nunca salva conta
        // incompatível com o kind final.
        let effectiveAccount: String?
        switch kind {
        case .claude:
            effectiveAccount = state.accounts(for: .claude).contains(where: { $0.path == account }) ? account : nil
        case .codex:
            effectiveAccount = state.accounts(for: .codex).contains(where: { $0.path == account }) ? account : nil
        case .shell:
            effectiveAccount = nil
        }
        // Normaliza defaults para nil: modelo enxuto, sem selo desnecessário.
        let msg = Message(
            text: t, kind: kind,
            model: kind == .claude && model != Message.defaultModel ? model : nil,
            effort: kind == .claude && effort != Message.defaultEffort ? effort : nil,
            safeMode: kind == .claude && safeMode != Message.defaultSafeMode ? safeMode : nil,
            configDir: kind != .shell ? effectiveAccount : nil,
            workingDir: kind != .shell && !workingDir.isEmpty ? workingDir : nil,
            showResponse: showResponse ? true : nil,
            codexModel: kind == .codex && !codexModel.trimmingCharacters(in: .whitespaces).isEmpty
                ? codexModel.trimmingCharacters(in: .whitespaces) : nil,
            codexReasoning: kind == .codex && codexReasoning != .low
                ? codexReasoning : nil)
        if let editing {
            state.updateFavorite(editing, to: msg)
            onDone(msg)
        } else {
            let created = state.addFavorite(text: t, kind: kind, model: msg.model, effort: msg.effort,
                              safeMode: msg.safeMode, configDir: msg.configDir,
                              workingDir: msg.workingDir, showResponse: msg.showResponse,
                              codexModel: msg.codexModel, codexReasoning: msg.codexReasoning)
            onDone(created)
        }
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
    let accountLabel: (URL) -> String

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
                    Text(accountLabel(dir)).tag(String?.some(dir.path))
                }
            }
            TextField("Diretório (~ por padrão)", text: $workingDir)
        }
        .font(.caption)
    }
}

/// Bloco de configuração de uma mensagem Codex (modelo/reasoning/conta/dir).
struct CodexConfigForm: View {
    @Binding var model: String        // vazio = default da conta (config.toml)
    @Binding var reasoning: Message.CodexReasoning
    @Binding var configDir: String?   // nil = ~/.codex
    @Binding var workingDir: String
    let accounts: [URL]
    let accountLabel: (URL) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Modelo (padrão da conta)", text: $model)
            Picker("Reasoning", selection: $reasoning) {
                ForEach(Message.CodexReasoning.allCases, id: \.self) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            Picker("Conta", selection: $configDir) {
                Text("Padrão (~/.codex)").tag(String?.none)
                ForEach(accounts, id: \.self) { dir in
                    Text(accountLabel(dir)).tag(String?.some(dir.path))
                }
            }
            TextField("Diretório (~ por padrão)", text: $workingDir)
        }
        .font(.caption)
    }
}
