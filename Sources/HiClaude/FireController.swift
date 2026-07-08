import Foundation

protocol FailureNotifying {
    func notifyFailure(message: String)
}

struct NullNotifier: FailureNotifying {
    func notifyFailure(message: String) {}
}

/// Orquestra um disparo: detector → (pula | executa) → registra em AppState.
@MainActor
final class FireController {
    private let state: AppState
    private let detector: SessionDetecting
    private let runner: ClaudeRunning
    private let notifier: FailureNotifying
    private let clock: Clock
    private var isRunning = false

    init(state: AppState, detector: SessionDetecting, runner: ClaudeRunning,
         notifier: FailureNotifying, clock: Clock = SystemClock()) {
        self.state = state
        self.detector = detector
        self.runner = runner
        self.notifier = notifier
        self.clock = clock
    }

    func fire(message: Message, origin: FireOrigin) async {
        guard !isRunning else { return } // disparo em andamento → ignora o novo
        isRunning = true
        defer { isRunning = false }

        let accountDir = state.effectiveConfigDir(for: message)
        let account = accountDir.lastPathComponent
        let projects = accountDir.appendingPathComponent("projects")

        // O skip por janela ativa só faz sentido no modo Claude (o objetivo é
        // abrir a janela de 5h). Comando cru sempre roda no horário.
        if message.kind == .claude, let end = await detector.activeWindowEnd(projectsDir: projects) {
            state.activeWindowEnd = end
            state.recordEvent(FireEvent(date: clock.now, result: .skipped(activeUntil: end),
                                        messageText: message.text, account: account, origin: origin))
            return
        }

        switch await runner.run(message) {
        case .success:
            state.claudeFound = true
            state.recordEvent(FireEvent(date: clock.now, result: .success,
                                        messageText: message.text, account: account, origin: origin))
            if message.kind == .claude {
                state.activeWindowEnd = await detector.activeWindowEnd(projectsDir: projects)
            }
        case .failure(let error):
            if error == .cliNotFound { state.claudeFound = false }
            state.recordEvent(FireEvent(date: clock.now, result: .failure(message: error.userMessage),
                                        messageText: message.text, account: account, origin: origin))
            if origin != .manual { notifier.notifyFailure(message: error.userMessage) }
        }
    }
}
