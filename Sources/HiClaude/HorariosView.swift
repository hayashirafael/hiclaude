import SwiftUI

/// Seção Horários: tarefas da agenda — comando em horários fixos × dias da
/// semana, independentes da renovação das contas.
struct HorariosView: View {
    @ObservedObject var state: AppState
    @State private var showingForm = false
    @State private var editing: ScheduledTask? = nil

    var body: some View {
        Group {
            if state.tasks.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .sheet(isPresented: $showingForm) {
            TaskFormSheet(state: state, editing: editing) { showingForm = false }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nenhuma tarefa ainda")
            Text("Tarefas disparam comandos em horários fixos, independentes da renovação das contas.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Nova tarefa") { editing = nil; showingForm = true }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(40)
    }

    private var list: some View {
        Form {
            Section {
                ForEach(state.tasks) { task in row(task) }
                Button {
                    editing = nil
                    showingForm = true
                } label: {
                    Label("Nova tarefa", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Cada tarefa roda seu comando nos horários e dias marcados. Claude/Codex pulam quando a janela da conta já está ativa.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ task: ScheduledTask) -> some View {
        HStack(alignment: .top) {
            Toggle("", isOn: enabledBinding(task))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(title(task))
                Text(subtitle(task)).font(.caption2).foregroundStyle(.secondary)
                if task.commandUID != nil, state.message(withUID: task.commandUID!) == nil {
                    Text("comando removido — usando o padrão (1+1)")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button { editing = task; showingForm = true } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            Button { state.tasks.removeAll { $0.uid == task.uid } } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private func title(_ task: ScheduledTask) -> String {
        task.name ?? state.resolvedTaskMessage(for: task).text
    }

    /// "Codex · 08:00 · 13:00 — seg a sex · próxima qua 08:00"
    private func subtitle(_ task: ScheduledTask) -> String {
        var parts: [String] = []
        switch state.resolvedTaskMessage(for: task).kind {
        case .claude: parts.append("Claude")
        case .codex: parts.append("Codex")
        case .shell: parts.append("comando")
        }
        let horarios = task.times.sorted().map(Fmt.minutes).joined(separator: " · ")
        parts.append("\(horarios) — \(Self.daysSummary(task.weekdays))")
        if task.enabled, let next = state.nextTaskFires[task.uid], next > Date() {
            parts.append("próxima \(Fmt.weekdayTime(next))")
        }
        return parts.joined(separator: " · ")
    }

    /// Resumo dos dias: "todos os dias", "seg a sex", "fim de semana" ou lista.
    static func daysSummary(_ weekdays: Set<Int>) -> String {
        if weekdays == Set(1...7) { return "todos os dias" }
        if weekdays == [2, 3, 4, 5, 6] { return "seg a sex" }
        if weekdays == [1, 7] { return "fim de semana" }
        let names = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
        return weekdays.sorted().map { names[$0 - 1] }.joined(separator: " · ")
    }

    private func enabledBinding(_ task: ScheduledTask) -> Binding<Bool> {
        Binding(
            get: { state.tasks.first { $0.uid == task.uid }?.enabled ?? false },
            set: { on in
                guard let idx = state.tasks.firstIndex(where: { $0.uid == task.uid }) else { return }
                state.tasks[idx].enabled = on
            })
    }
}

/// Formulário de criação/edição de tarefa, em sheet.
struct TaskFormSheet: View {
    @ObservedObject var state: AppState
    let editing: ScheduledTask?
    let onDone: () -> Void

    @State private var name = ""
    @State private var commandUID: UUID? = nil
    @State private var times: [Int] = [9 * 60]
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var enabled = true
    @State private var showingNewCommand = false

    /// Tag sentinela do item "Novo…" no picker (mesmo padrão de ContasView).
    private static let newCommandSentinel = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

    private static let dayLetters = ["D", "S", "T", "Q", "Q", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? "Nova tarefa" : "Editar tarefa").font(.headline)
            TextField("Nome (opcional)", text: $name)
            commandPicker
            timesEditor
            weekdaysEditor
            Toggle("Habilitada", isOn: $enabled).toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Cancelar") { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Adicionar" : "Salvar") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(times.isEmpty || weekdays.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear(perform: load)
        .sheet(isPresented: $showingNewCommand) {
            MessageFormSheet(state: state, editing: nil) { created in
                if let created { commandUID = created.uid }
                showingNewCommand = false
            }
        }
    }

    private var commandPicker: some View {
        Picker("Comando", selection: commandBinding) {
            Text(AppState.defaultMessage.text).tag(UUID?.none)
            ForEach(state.favorites) { msg in
                Text(msg.text).tag(msg.uid)
            }
            Divider()
            Text("Novo…").tag(UUID?.some(Self.newCommandSentinel))
        }
    }

    private var commandBinding: Binding<UUID?> {
        Binding(
            get: { commandUID },
            set: { uid in
                if uid == Self.newCommandSentinel { showingNewCommand = true }
                else { commandUID = uid }
            })
    }

    private var timesEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(times.indices, id: \.self) { idx in
                HStack {
                    DatePicker("Horário", selection: timeBinding(idx),
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
                Label("Adicionar horário", systemImage: "plus.circle")
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
            Text("Dias").font(.caption)
            ForEach(1...7, id: \.self) { day in
                Toggle(Self.dayLetters[day - 1], isOn: dayBinding(day))
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

    private func load() {
        guard let t = editing else { return }
        name = t.name ?? ""
        commandUID = t.commandUID
        times = t.times
        weekdays = t.weekdays
        enabled = t.enabled
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var task = ScheduledTask(uid: editing?.uid ?? UUID(),
                                 name: trimmed.isEmpty ? nil : trimmed,
                                 commandUID: commandUID,
                                 times: times.sorted(), weekdays: weekdays,
                                 enabled: enabled)
        if let editing, let idx = state.tasks.firstIndex(where: { $0.uid == editing.uid }) {
            task.uid = editing.uid
            state.tasks[idx] = task
        } else {
            state.tasks.append(task)
        }
        onDone()
    }
}
