import SwiftUI

/// Seção Horários: todos os agendamentos — contínuos (janela de 5h) e de
/// horários fixos × dias da semana — num único lugar.
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
            AgendamentoFormSheet(state: state, editing: editing) { showingForm = false }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Nenhum agendamento ainda")
            Text("Agendamentos disparam comandos de forma contínua (a cada janela de 5h da conta) ou em horários fixos.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Novo agendamento") { editing = nil; showingForm = true }
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
                    Label("Novo agendamento", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            } footer: {
                Text("Contínuo renova a janela de 5h da conta 24/7; horários fixos disparam nos horários e dias marcados. Claude/Codex pulam quando a janela da conta já está ativa.")
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
                if task.resolvedCommand.kind != .shell,
                   let cfg = task.resolvedCommand.configDir, !cfg.isEmpty,
                   state.accountDir(for: task) == nil {
                    Text("pasta da conta não encontrada — o agendamento não dispara")
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
        task.name ?? task.resolvedCommand.text
    }

    /// "Codex · conta X · contínua · renova 14:05" ou
    /// "Claude · 08:00 · 13:00 — seg a sex · próxima qua 08:00".
    private func subtitle(_ task: ScheduledTask) -> String {
        var parts: [String] = []
        switch task.resolvedCommand.kind {
        case .claude: parts.append("Claude")
        case .codex: parts.append("Codex")
        case .shell: parts.append("comando")
        }
        if let dir = state.accountDir(for: task) { parts.append(state.label(for: dir)) }
        switch task.repetition {
        case .continuous:
            parts.append("contínua")
            if task.enabled, let dir = state.accountDir(for: task),
               let next = state.nextRenewals[dir], next > Date() {
                parts.append("renova \(Fmt.hhmm(next))")
            } else if task.enabled {
                parts.append("aguardando janela")
            }
        case .fixed:
            let horarios = task.times.sorted().map(Fmt.minutes).joined(separator: " · ")
            parts.append("\(horarios) — \(Self.daysSummary(task.weekdays))")
            if task.enabled, let next = state.nextTaskFires[task.uid], next > Date() {
                parts.append("próxima \(Fmt.weekdayTime(next))")
            }
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
