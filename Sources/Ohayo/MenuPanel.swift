import SwiftUI

/// Painel do menu da barra (.window): um card por conta agendada com o
/// status da janela de 5h e o próximo evento; ações por conta no hover;
/// rodapé com atalhos globais. Substitui o menu nativo (MenuContent).
struct MenuPanel: View {
    @ObservedObject var state: AppState
    let env: AppEnvironment
    @Environment(\.openWindow) private var openWindow
    @State private var hovered: URL?
    private var strings: L10n { state.strings }

    private var accounts: [URL] {
        MenuPanelLogic.scheduledAccounts(
            tasks: state.tasks,
            accountDir: { state.accountDir(for: $0) },
            label: { state.label(for: $0) })
    }

    var body: some View {
        VStack(spacing: 7) {
            header
            if accounts.isEmpty {
                Text(strings.noActiveSchedules)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ForEach(accounts, id: \.self) { card($0) }
            }
            footer
        }
        .padding(10)
        .frame(width: 310)
        .onAppear {
            hovered = nil
            Task { await env.refreshWindowEnds() }
        }
    }

    // MARK: - Cabeçalho ("Ohayo" ou aviso de CLI + botão Sair)

    private var header: some View {
        HStack {
            Text(headerTitle)
                .font(.caption)
                .foregroundStyle(state.missingCLIs.isEmpty ? .secondary : Color.orange)
                .lineLimit(1)
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help(strings.quit)
        }
        .padding(.horizontal, 2)
    }

    private var headerTitle: String {
        if let missing = state.missingCLIs.first {
            return strings.installCLIWarning(missing)
        }
        return "Ohayo"
    }

    // MARK: - Card por conta

    private func card(_ dir: URL) -> some View {
        let paused = state.isPaused(dir)
        let windowEnd = state.windowEnds[dir.standardizedFileURL].flatMap { $0 > Date() ? $0 : nil }
        let event = MenuPanelLogic.nextEvent(
            for: dir, tasks: state.tasks,
            nextRenewals: state.nextRenewals, nextTaskFires: state.nextTaskFires,
            accountDir: { state.accountDir(for: $0) }, now: Date(),
            renewalFallbackName: strings.renewalFallbackName)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                providerMark(dir, paused: paused, active: windowEnd != nil)
                Text(state.label(for: dir))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if hovered != dir {
                    trailing(paused: paused, windowEnd: windowEnd)
                }
            }
            Text(eventLine(event))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 28)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(.quaternary.opacity(hovered == dir ? 0.9 : 0.5),
                    in: RoundedRectangle(cornerRadius: 9))
        .opacity(paused && hovered != dir ? 0.55 : 1)
        .overlay(alignment: .trailing) {
            if hovered == dir { hoverActions(dir, paused: paused).padding(.trailing, 9) }
        }
        .onHover { hovered = $0 ? dir : nil }
    }

    /// Ícone do provider com a bolinha de status no canto: verde = janela
    /// ativa, cinza = aguardando, laranja = pausada.
    private func providerMark(_ dir: URL, paused: Bool, active: Bool) -> some View {
        ProviderIcon(provider: state.provider(for: dir), size: 16)
            .frame(width: 20, height: 20)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(paused ? Color.orange : (active ? Color.green : Color.secondary))
                    .frame(width: 7, height: 7)
                    .offset(x: 2, y: 2)
            }
    }

    @ViewBuilder
    private func trailing(paused: Bool, windowEnd: Date?) -> some View {
        if paused {
            Text(strings.pausedBadge)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
        } else if let windowEnd {
            Text(Fmt.remaining(until: windowEnd, from: Date()))
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.green)
        } else {
            Text("—").font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }

    private func eventLine(_ event: (name: String, date: Date)?) -> String {
        guard let event else { return strings.waitingForWindow }
        return "\(event.name) · \(Fmt.hhmm(event.date, language: state.language))"
    }

    /// Ações no hover: pausar/retomar · tarefas da conta · histórico da conta.
    private func hoverActions(_ dir: URL, paused: Bool) -> some View {
        HStack(spacing: 4) {
            hoverButton(paused ? "play.fill" : "pause.fill",
                        help: paused ? strings.resumeAccount : strings.pauseAccount) {
                state.setPaused(dir, !paused)
            }
            hoverButton("checklist", help: strings.accountTasks) {
                open(.horarios, filter: dir)
            }
            hoverButton("clock.arrow.circlepath", help: strings.accountHistory) {
                open(.historico, filter: dir)
            }
        }
    }

    private func hoverButton(_ symbol: String, help: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Rodapé (Tarefas · Histórico · Ajustes)

    private var footer: some View {
        HStack(spacing: 7) {
            footerButton("checklist", strings.schedules) { open(.horarios, filter: nil) }
            footerButton("clock.arrow.circlepath", strings.history) { open(.historico, filter: nil) }
            footerButton("gearshape", strings.settingsShort) { open(.geral, filter: nil) }
        }
        .padding(.top, 3)
        .overlay(alignment: .top) { Divider().offset(y: -3) }
    }

    private func footerButton(_ symbol: String, _ title: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navegação

    private func open(_ section: SettingsSection, filter: URL?) {
        state.accountFilter = filter
        state.settingsSection = section
        openWindow(id: "schedule")
        NSApp.activate(ignoringOtherApps: true)
        closePanel()
    }

    /// O painel .window do MenuBarExtra não fecha sozinho ao abrir outra
    /// janela — fecha a janela do próprio painel explicitamente.
    private func closePanel() {
        NSApp.windows.first { $0.className.contains("MenuBarExtraWindow") }?.close()
    }
}
