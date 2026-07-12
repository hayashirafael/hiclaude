import SwiftUI

/// Formulário único de agendamento: tipo (Claude/Codex/Comando), prompt com
/// personalização por tipo, e repetição (contínua ou horários fixos).
struct AgendamentoFormSheet: View {
    static let initialCommandText = ""

    enum OutputMode: Equatable {
        case none
        case terminal
        case response
    }

    static let initialOutputMode: OutputMode = .none

    static func outputMode(for message: Message) -> OutputMode {
        if message.kind != .shell && message.resolvedRunInTerminal { return .terminal }
        if message.resolvedShowResponse { return .response }
        return .none
    }

    @ObservedObject var state: AppState
    /// Agendamento em edição; nil = modo "adicionar".
    let editing: ScheduledTask?
    let onDone: () -> Void

    @State private var name = ""
    @State private var text = Self.initialCommandText
    @State private var kind: Message.Kind = .claude
    @State private var model: Message.Model = Message.defaultModel
    @State private var effort: Message.Effort = Message.defaultEffort
    @State private var safeMode = Message.defaultSafeMode
    @State private var codexModel = ""
    @State private var codexReasoning: Message.CodexReasoning = .low
    @State private var outputMode: OutputMode = Self.initialOutputMode
    @State private var notifyOnSuccess = false
    @State private var account: String? = nil
    @State private var skill: String? = nil
    @State private var availableSkills: [SkillRef] = []
    @State private var workingDir = ""
    @State private var repetition: ScheduledTask.Repetition = .fixed
    @State private var times: [Int] = [9 * 60]
    @State private var weekdays: Set<Int> = Set(1...7)
    @State private var enabled = true

    private var strings: L10n { state.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing == nil ? strings.newSchedule : strings.editSchedule).font(.headline)

            sectionHeader(strings.messageSection)
            KindSelector(kind: $kind, strings: strings)
            TextField(strings.nameOptional, text: $name)
            TextField(strings.messageOrCommand, text: $text)
            if kind == .claude {
                ClaudeConfigForm(model: $model, effort: $effort, safeMode: $safeMode,
                                 configDir: $account, skill: $skill,
                                 availableSkills: availableSkills,
                                 workingDir: $workingDir,
                                 accounts: state.accounts(for: .claude),
                                 accountLabel: { state.label(for: $0) },
                                 strings: strings)
            }
            if kind == .codex {
                CodexConfigForm(model: $codexModel, reasoning: $codexReasoning,
                                configDir: $account, skill: $skill,
                                availableSkills: availableSkills,
                                workingDir: $workingDir,
                                accounts: state.accounts(for: .codex),
                                accountLabel: { state.label(for: $0) },
                                strings: strings)
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle(strings.none, isOn: outputModeBinding(.none))
                    .toggleStyle(.checkbox)
                if kind != .shell {
                    Toggle(strings.runInTerminal, isOn: outputModeBinding(.terminal))
                        .toggleStyle(.checkbox)
                }
                Toggle(strings.showResponse, isOn: outputModeBinding(.response))
                    .toggleStyle(.checkbox)
                // Independente do modo de saída acima: notifica só em sucesso;
                // com "Mostrar resposta" ligado, a notificação de resposta vence.
                Toggle(strings.notifyOnSuccess, isOn: $notifyOnSuccess)
                    .toggleStyle(.checkbox)
            }
            .font(.caption)

            Divider().padding(.vertical, 2)

            sectionHeader(strings.scheduleSection)
            repetitionPicker
            if repetition == .fixed {
                TimeChipsEditor(times: $times, strings: strings)
                weekdaysEditor
                dayPresetsRow
                if overlapWarning {
                    Label(strings.overlappingWindows, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let preview = nextFirePreview {
                    Text(preview).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(strings.fixedContinuousDescription)
                    .font(.caption).foregroundStyle(.secondary)
                if continuousConflict {
                    Label(strings.continuousConflict,
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Toggle(strings.enabled, isOn: $enabled)
                .toggleStyle(.checkbox)
                .font(.caption)

            HStack {
                Spacer()
                Button(strings.cancel) { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? strings.add : strings.save) { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
                    .help(saveDisabledReason ?? "")
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            load()
            refreshSkills()
        }
        // Conta é por provider; trocar o Tipo sem limpar conta incompatível
        // persistiria um configDir do provider errado. Shell não mira conta e
        // não pode ser contínuo.
        .onChange(of: kind) { newKind in
            // Troca de tipo: revarre e limpa skill que não existe no novo
            // provider (mesmo padrão da conta incompatível). Troca só de
            // conta mantém a skill, com aviso no form.
            defer {
                refreshSkills()
                if let current = skill,
                   !availableSkills.contains(where: { $0.name == current }) {
                    skill = nil
                }
            }
            if newKind == .shell {
                account = nil
                if outputMode == .terminal { outputMode = .none }
                if repetition == .continuous { repetition = .fixed }
                return
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
        .onChange(of: account) { _ in refreshSkills() }
        .onChange(of: skill) { newSkill in
            // Skill exige safe-mode desligado; limpar a skill não religa
            // sozinho (o usuário reabilita o toggle se quiser).
            if newSkill?.isEmpty == false { safeMode = false }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func outputModeBinding(_ mode: OutputMode) -> Binding<Bool> {
        Binding(
            get: { outputMode == mode },
            set: { selected in
                if selected { outputMode = mode }
            })
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

    private var weekdaysEditor: some View {
        HStack(spacing: 4) {
            Text(strings.days).font(.caption)
            ForEach(1...7, id: \.self) { day in
                Toggle(strings.dayLetters[day - 1], isOn: dayBinding(day))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    // As letras únicas (D S T Q Q S S) são ambíguas: o nome
                    // completo desambigua no hover e para leitores de tela.
                    .help(strings.dayName(day))
                    .accessibilityLabel(strings.dayName(day))
            }
        }
    }

    private func dayBinding(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { weekdays.contains(day) },
            set: { on in if on { weekdays.insert(day) } else { weekdays.remove(day) } })
    }

    /// Atalhos com o mesmo vocabulário do resumo de dias da lista.
    private var dayPresetsRow: some View {
        HStack(spacing: 12) {
            dayPresetButton(Set(1...7))
            dayPresetButton([2, 3, 4, 5, 6])
            dayPresetButton([1, 7])
        }
        .font(.caption)
    }

    private func dayPresetButton(_ preset: Set<Int>) -> some View {
        Button(strings.daysSummary(preset)) { weekdays = preset }
            .buttonStyle(.link)
            .disabled(weekdays == preset)
    }

    private var continuousConflict: Bool {
        state.hasContinuousConflict(draftTask())
    }

    /// Aviso não bloqueante: dois horários dentro da mesma janela de 5h.
    /// Só para Claude/Codex — shell não abre janela.
    private var overlapWarning: Bool {
        guard kind != .shell, repetition == .fixed,
              let gap = AgendaMath.minCircularGap(times) else { return false }
        return gap < 300
    }

    private var nextFirePreview: String? {
        guard repetition == .fixed,
              let next = AgendaMath.nextOccurrence(times: times, weekdays: weekdays,
                                                   after: Date(), calendar: .current)
        else { return nil }
        return strings.nextAt(Fmt.weekdayTime(next, language: state.language))
    }

    private var isValid: Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch repetition {
        case .fixed: return !times.isEmpty && !weekdays.isEmpty
        case .continuous: return kind != .shell && !continuousConflict
        }
    }

    /// Motivo de o Salvar estar desabilitado (tooltip); nil quando válido.
    private var saveDisabledReason: String? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return strings.saveNeedsMessage
        }
        switch repetition {
        case .fixed:
            if times.isEmpty { return strings.saveNeedsTime }
            if weekdays.isEmpty { return strings.saveNeedsDay }
        case .continuous:
            if continuousConflict { return strings.continuousConflict }
        }
        return nil
    }

    /// Recalcula as skills da conta alvo (abrir o sheet / trocar conta /
    /// trocar tipo). Conta nil = default global do provider — o mesmo
    /// diretório que o dispatch resolveria.
    private func refreshSkills() {
        guard kind != .shell else {
            availableSkills = []
            return
        }
        let provider: Provider = kind == .codex ? .codex : .claude
        let dir = account.map { URL(fileURLWithPath: $0) }
            ?? (provider == .codex ? AppState.defaultCodexConfigDir : AppState.defaultConfigDir)
        availableSkills = SkillCatalog.skills(for: provider, at: dir)
    }

    private func load() {
        guard let t = editing else { return }
        name = t.name ?? ""
        repetition = t.repetition
        times = AgendaMath.normalized(t.times.isEmpty ? [9 * 60] : t.times)
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
        outputMode = Self.outputMode(for: msg)
        notifyOnSuccess = msg.notifyOnSuccess ?? false
        account = msg.configDir
        skill = msg.skill
        workingDir = msg.workingDir ?? ""
    }

    /// Monta o agendamento normalizando defaults para nil.
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
            showResponse: outputMode == .response ? true : nil,
            runInTerminal: kind != .shell && outputMode != .terminal ? false : nil,
            notifyOnSuccess: notifyOnSuccess ? true : nil,
            codexModel: kind == .codex && !codexModel.trimmingCharacters(in: .whitespaces).isEmpty
                ? codexModel.trimmingCharacters(in: .whitespaces) : nil,
            codexReasoning: kind == .codex && codexReasoning != .low ? codexReasoning : nil,
            skill: kind != .shell && skill?.isEmpty == false ? skill : nil)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var task = ScheduledTask(uid: editing?.uid ?? UUID(),
                                 name: trimmedName.isEmpty ? nil : trimmedName,
                                 command: command,
                                 repetition: repetition,
                                 times: repetition == .fixed ? times : [],
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

/// Seletor segmentado desenhado à mão: o `Picker(.segmented)` do macOS descarta
/// a imagem custom do `Label` (só o texto sobrevive), então os segmentos são
/// botões próprios para exibir o `ProviderIcon` de cada tipo.
struct KindSelector: View {
    @Binding var kind: Message.Kind
    let strings: L10n

    var body: some View {
        HStack(spacing: 2) {
            segment(.claude, title: "Claude", provider: .claude)
            segment(.codex, title: "Codex", provider: .codex)
            segment(.shell, title: strings.command, provider: nil)
        }
        .padding(2)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
    }

    private func segment(_ value: Message.Kind, title: String, provider: Provider?) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { kind = value }
        } label: {
            HStack(spacing: 5) {
                ProviderIcon(provider: provider, size: 12)
                Text(title)
            }
            .font(.callout)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(kind == value ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .background {
            if kind == value {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            }
        }
    }
}
