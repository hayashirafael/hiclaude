import AppKit
import SwiftUI

/// Formulário único de agendamento: tipo (Claude/Codex/Comando), prompt com
/// personalização por tipo, e repetição (contínua ou horários fixos).
struct AgendamentoFormSheet: View {
    @ObservedObject var state: AppState
    /// Agendamento em edição; nil = modo "adicionar".
    let editing: ScheduledTask?
    let onDone: () -> Void

    @State private var name = ""
    @State private var text = "1+1"
    @State private var kind: Message.Kind = .claude
    @State private var model: Message.Model = Message.defaultModel
    @State private var effort: Message.Effort = Message.defaultEffort
    @State private var safeMode = Message.defaultSafeMode
    @State private var codexModel = ""
    @State private var codexReasoning: Message.CodexReasoning = .low
    @State private var showResponse = false
    @State private var runInTerminal = true
    @State private var account: String? = nil
    @State private var workingDir = ""
    @State private var repetition: ScheduledTask.Repetition = .fixed
    @State private var times: [Int] = [9 * 60]
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var enabled = true

    private var strings: L10n { state.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? strings.newSchedule : strings.editSchedule).font(.headline)
            TextField(strings.nameOptional, text: $name)
            TextField(strings.messageOrCommand, text: $text)
            Picker(strings.type, selection: $kind) {
                Text("Claude").tag(Message.Kind.claude)
                Text("Codex").tag(Message.Kind.codex)
                Text(strings.command).tag(Message.Kind.shell)
            }
            .pickerStyle(.segmented)
            if kind == .claude {
                ClaudeConfigForm(model: $model, effort: $effort, safeMode: $safeMode,
                                 configDir: $account, workingDir: $workingDir,
                                 accounts: state.accounts(for: .claude),
                                 accountLabel: { state.label(for: $0) },
                                 strings: strings)
            }
            if kind == .codex {
                CodexConfigForm(model: $codexModel, reasoning: $codexReasoning,
                                configDir: $account, workingDir: $workingDir,
                                accounts: state.accounts(for: .codex),
                                accountLabel: { state.label(for: $0) },
                                strings: strings)
            }
            if kind != .shell {
                Toggle(strings.runInTerminal, isOn: $runInTerminal)
                    .toggleStyle(.checkbox)
            }
            Toggle(strings.showResponse, isOn: $showResponse)
                .toggleStyle(.checkbox)
                .disabled(kind != .shell && runInTerminal)
            Divider()
            repetitionPicker
            if repetition == .fixed {
                timesEditor
                weekdaysEditor
            } else {
                Text(strings.fixedContinuousDescription)
                    .font(.caption).foregroundStyle(.secondary)
                if continuousConflict {
                    Label(strings.continuousConflict,
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Toggle(strings.enabled, isOn: $enabled).toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button(strings.cancel) { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? strings.add : strings.save) { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear(perform: load)
        // Conta é por provider; trocar o Tipo sem limpar conta incompatível
        // persistiria um configDir do provider errado (mesma lógica do antigo
        // MessageFormSheet). Shell não mira conta e não pode ser contínuo.
        .onChange(of: kind) { newKind in
            if newKind == .shell {
                account = nil
                runInTerminal = false
                if repetition == .continuous { repetition = .fixed }
                return
            } else if editing == nil || editing?.resolvedCommand.kind == .shell {
                runInTerminal = true
            }
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

    private var repetitionPicker: some View {
        Picker(strings.repetition, selection: $repetition) {
            Text(strings.fixedTimes).tag(ScheduledTask.Repetition.fixed)
            if kind != .shell {
                Text(strings.continuousWindow).tag(ScheduledTask.Repetition.continuous)
            }
        }
        .pickerStyle(.segmented)
    }

    private var timesEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(times.indices, id: \.self) { idx in
                HStack {
                    DatePicker(strings.time, selection: timeBinding(idx),
                               displayedComponents: .hourAndMinute)
                    if times.count > 1 {
                        Button { times.remove(at: idx) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                times.append((times.max() ?? 9 * 60) + 60)
            } label: {
                Label(strings.addTime, systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
    }

    private func timeBinding(_ idx: Int) -> Binding<Date> {
        Binding(
            get: {
                let m = times[idx]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60,
                                             second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let p = Calendar.current.dateComponents([.hour, .minute], from: date)
                times[idx] = (p.hour ?? 0) * 60 + (p.minute ?? 0)
            })
    }

    private var weekdaysEditor: some View {
        HStack(spacing: 4) {
            Text(strings.days).font(.caption)
            ForEach(1...7, id: \.self) { day in
                Toggle(strings.dayLetters[day - 1], isOn: dayBinding(day))
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
        }
    }

    private func dayBinding(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { weekdays.contains(day) },
            set: { on in if on { weekdays.insert(day) } else { weekdays.remove(day) } })
    }

    private var continuousConflict: Bool {
        state.hasContinuousConflict(draftTask())
    }

    private var isValid: Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch repetition {
        case .fixed: return !times.isEmpty && !weekdays.isEmpty
        case .continuous: return kind != .shell && !continuousConflict
        }
    }

    private func load() {
        guard let t = editing else { return }
        name = t.name ?? ""
        repetition = t.repetition
        times = t.times.isEmpty ? [9 * 60] : t.times
        weekdays = t.weekdays.isEmpty ? Set(1...7) : t.weekdays
        enabled = t.enabled
        let msg = t.resolvedCommand
        text = msg.text
        kind = msg.kind
        model = msg.resolvedModel
        effort = msg.resolvedEffort
        safeMode = msg.resolvedSafeMode
        codexModel = msg.codexModel ?? ""
        codexReasoning = msg.codexReasoning ?? .low
        showResponse = msg.resolvedShowResponse
        runInTerminal = msg.resolvedRunInTerminal
        account = msg.configDir
        workingDir = msg.workingDir ?? ""
    }

    /// Monta o agendamento a partir do estado do formulário (normalizando
    /// defaults para nil — prompt embutido enxuto, mesma regra do antigo
    /// MessageFormSheet.commit).
    private func draftTask() -> ScheduledTask {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveAccount: String?
        switch kind {
        case .claude:
            effectiveAccount = state.accounts(for: .claude).contains(where: { $0.path == account }) ? account : nil
        case .codex:
            effectiveAccount = state.accounts(for: .codex).contains(where: { $0.path == account }) ? account : nil
        case .shell:
            effectiveAccount = nil
        }
        let command = Message(
            text: t, kind: kind,
            model: kind == .claude && model != Message.defaultModel ? model : nil,
            effort: kind == .claude && effort != Message.defaultEffort ? effort : nil,
            safeMode: kind == .claude && safeMode != Message.defaultSafeMode ? safeMode : nil,
            configDir: kind != .shell ? effectiveAccount : nil,
            workingDir: kind != .shell && !workingDir.isEmpty ? workingDir : nil,
            showResponse: showResponse && !(kind != .shell && runInTerminal) ? true : nil,
            runInTerminal: kind != .shell && !runInTerminal ? false : nil,
            codexModel: kind == .codex && !codexModel.trimmingCharacters(in: .whitespaces).isEmpty
                ? codexModel.trimmingCharacters(in: .whitespaces) : nil,
            codexReasoning: kind == .codex && codexReasoning != .low ? codexReasoning : nil)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var task = ScheduledTask(uid: editing?.uid ?? UUID(),
                                 name: trimmedName.isEmpty ? nil : trimmedName,
                                 command: command,
                                 repetition: repetition,
                                 times: repetition == .fixed ? times.sorted() : [],
                                 weekdays: repetition == .fixed ? weekdays : [])
        task.enabled = enabled
        return task
    }

    private func commit() {
        let task = draftTask()
        if let editing, let idx = state.tasks.firstIndex(where: { $0.uid == editing.uid }) {
            state.tasks[idx] = task
        } else {
            state.tasks.append(task)
        }
        onDone()
    }
}

/// Bloco de configuração de uma mensagem Claude (modelo/effort/safe/conta/dir).
struct ClaudeConfigForm: View {
    @Binding var model: Message.Model
    @Binding var effort: Message.Effort
    @Binding var safeMode: Bool
    @Binding var configDir: String?   // nil = conta global
    @Binding var workingDir: String
    let accounts: [URL]
    let accountLabel: (URL) -> String
    let strings: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(strings.model, selection: $model) {
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
            Picker(strings.account, selection: $configDir) {
                Text(strings.globalDefault).tag(String?.none)
                ForEach(accounts, id: \.self) { dir in
                    Text(accountLabel(dir)).tag(String?.some(dir.path))
                }
            }
            WorkingDirectoryPicker(workingDir: $workingDir, strings: strings)
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
    let strings: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(strings.accountDefaultModel, text: $model)
            Picker("Reasoning", selection: $reasoning) {
                ForEach(Message.CodexReasoning.allCases, id: \.self) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            Picker(strings.account, selection: $configDir) {
                Text(strings.codexDefault).tag(String?.none)
                ForEach(accounts, id: \.self) { dir in
                    Text(accountLabel(dir)).tag(String?.some(dir.path))
                }
            }
            WorkingDirectoryPicker(workingDir: $workingDir, strings: strings)
        }
        .font(.caption)
    }
}

/// Campo de diretório de trabalho: mostra o caminho escolhido e abre o
/// seletor nativo do macOS para escolher uma pasta.
struct WorkingDirectoryPicker: View {
    @Binding var workingDir: String
    let strings: L10n

    private var isEmpty: Bool {
        workingDir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayText: String {
        if isEmpty { return strings.workingDirectoryDefault }
        return (workingDir as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                chooseDirectory()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(displayText)
                        .foregroundStyle(isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .help(strings.workingDirectoryDefault)

            if !isEmpty {
                Button {
                    workingDir = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help(strings.clearWorkingDirectory)
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = strings.chooseDirectory
        panel.directoryURL = initialDirectoryURL()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workingDir = url.standardizedFileURL.path
    }

    private func initialDirectoryURL() -> URL {
        guard !isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        let expanded = NSString(string: workingDir).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return URL(fileURLWithPath: expanded)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
