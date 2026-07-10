import SwiftUI

/// Seção Horários: todos os agendamentos — contínuos (janela de 5h) e de
/// horários fixos × dias da semana — num único lugar.
struct HorariosView: View {
    @ObservedObject var state: AppState
    @State private var showingForm = false
    @State private var editing: ScheduledTask? = nil
    @State private var conflictAlert = false
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
        .alert(strings.continuousConflictTitle, isPresented: $conflictAlert) {
            Button(strings.ok, role: .cancel) {}
        } message: {
            Text(strings.continuousConflict)
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
        let msg = task.resolvedCommand
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: enabledBinding(task))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            ProviderIcon(provider: provider(for: msg.kind), size: 20)
                .foregroundStyle(task.enabled ? .primary : .secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title(task))
                        .fontWeight(.medium)
                        .foregroundStyle(task.enabled ? .primary : .secondary)
                    repetitionBadge(task)
                }
                if task.name != nil, !msg.text.isEmpty {
                    Text(msg.text)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                if let target = targetLine(task) {
                    detailLabel(target, systemImage: "person.crop.circle")
                }
                detailLabel(scheduleLine(task),
                            systemImage: task.repetition == .continuous
                                ? "arrow.triangle.2.circlepath" : "clock")
                if let next = nextLine(task) {
                    Label(next, systemImage: "arrow.right.circle")
                        .font(.caption2).foregroundStyle(.tint)
                }
                if msg.kind != .shell,
                   let cfg = msg.configDir, !cfg.isEmpty,
                   state.accountDir(for: task) == nil {
                    Label(strings.accountFolderMissing,
                          systemImage: "exclamationmark.triangle")
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
        .padding(.vertical, 2)
    }

    private func detailLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2).foregroundStyle(.secondary)
    }

    private func repetitionBadge(_ task: ScheduledTask) -> some View {
        Text(task.repetition == .continuous ? strings.continuousBadge : strings.fixedTimes)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.12), in: Capsule())
    }

    private func title(_ task: ScheduledTask) -> String {
        task.name ?? task.resolvedCommand.text
    }

    private func provider(for kind: Message.Kind) -> Provider? {
        switch kind {
        case .claude: return .claude
        case .codex: return .codex
        case .shell: return nil
        }
    }

    /// Conta + modelo do disparo: "ailton@… · Haiku 4.5 · low" (Claude),
    /// "conta · gpt-x" (Codex). Shell não mira conta → nil.
    private func targetLine(_ task: ScheduledTask) -> String? {
        let msg = task.resolvedCommand
        guard msg.kind != .shell else { return nil }
        var parts: [String] = []
        if let dir = state.accountDir(for: task) {
            parts.append(state.label(for: dir))
        } else {
            parts.append(msg.kind == .claude ? strings.globalDefault : strings.codexDefault)
        }
        switch msg.kind {
        case .claude:
            parts.append("\(msg.resolvedModel.label) · \(msg.resolvedEffort.rawValue)")
        case .codex:
            if let model = msg.codexModel, !model.isEmpty { parts.append(model) }
        case .shell:
            break
        }
        return parts.joined(separator: " · ")
    }

    /// "17:14 · every day" (fixos) ou a descrição da janela contínua.
    private func scheduleLine(_ task: ScheduledTask) -> String {
        switch task.repetition {
        case .continuous:
            return strings.fixedContinuousDescription
        case .fixed:
            let horarios = task.times.sorted().map(Fmt.minutes).joined(separator: " · ")
            return "\(horarios) — \(Self.daysSummary(task.weekdays, language: state.language))"
        }
    }

    /// Próximo disparo: "next Sat 17:14", "renews 14:05" ou "waiting for window".
    private func nextLine(_ task: ScheduledTask) -> String? {
        guard task.enabled else { return nil }
        switch task.repetition {
        case .continuous:
            if let dir = state.accountDir(for: task),
               let next = state.nextRenewals[dir], next > Date() {
                return strings.renewsAt(Fmt.hhmm(next, language: state.language))
            }
            return strings.waitingForWindow
        case .fixed:
            guard let next = state.nextTaskFires[task.uid], next > Date() else { return nil }
            return strings.nextAt(Fmt.weekdayTime(next, language: state.language))
        }
    }

    /// Resumo dos dias: "todos os dias", "seg a sex", "fim de semana" ou lista.
    static func daysSummary(_ weekdays: Set<Int>, language: AppLanguage = .english) -> String {
        L10n(language: language).daysSummary(weekdays)
    }

    private func enabledBinding(_ task: ScheduledTask) -> Binding<Bool> {
        Binding(
            get: { state.tasks.first { $0.uid == task.uid }?.enabled ?? false },
            set: { on in
                if !state.setTaskEnabled(task, on) { conflictAlert = true }
            })
    }
}
