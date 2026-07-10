import SwiftUI

/// Seção Horários: todos os agendamentos — contínuos (janela de 5h) e de
/// horários fixos × dias da semana — num único lugar.
struct HorariosView: View {
    @ObservedObject var state: AppState
    @State private var showingForm = false
    @State private var editing: ScheduledTask? = nil
    private var strings: L10n { state.strings }

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
            Text(strings.noSchedulesYet)
            Text(strings.noSchedulesDescription)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(strings.newSchedule) { editing = nil; showingForm = true }
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
                    Label(strings.newSchedule, systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
            } footer: {
                Text(strings.scheduleListFooter)
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
                    Text(strings.accountFolderMissing)
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
        case .claude, .codex, .shell: parts.append(strings.taskKind(task.resolvedCommand.kind))
        }
        if let dir = state.accountDir(for: task) { parts.append(state.label(for: dir)) }
        switch task.repetition {
        case .continuous:
            parts.append(strings.continuous)
            if task.enabled, let dir = state.accountDir(for: task),
               let next = state.nextRenewals[dir], next > Date() {
                parts.append(strings.renewsAt(Fmt.hhmm(next, language: state.language)))
            } else if task.enabled {
                parts.append(strings.waitingForWindow)
            }
        case .fixed:
            let horarios = task.times.sorted().map(Fmt.minutes).joined(separator: " · ")
            parts.append("\(horarios) - \(Self.daysSummary(task.weekdays, language: state.language))")
            if task.enabled, let next = state.nextTaskFires[task.uid], next > Date() {
                parts.append(strings.nextAt(Fmt.weekdayTime(next, language: state.language)))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Resumo dos dias: "todos os dias", "seg a sex", "fim de semana" ou lista.
    static func daysSummary(_ weekdays: Set<Int>, language: AppLanguage = .english) -> String {
        L10n(language: language).daysSummary(weekdays)
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
