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

    func fire(manual: Bool) async {
        guard !isRunning else { return } // disparo em andamento → ignora o novo
        isRunning = true
        defer { isRunning = false }

        if let end = await detector.activeWindowEnd() {
            state.activeWindowEnd = end
            state.lastEvent = FireEvent(date: clock.now, result: .skipped(activeUntil: end))
            return
        }

        switch await runner.sendHi() {
        case .success:
            state.claudeFound = true
            state.lastEvent = FireEvent(date: clock.now, result: .success)
            state.activeWindowEnd = await detector.activeWindowEnd()
        case .failure(let error):
            if error == .cliNotFound { state.claudeFound = false }
            state.lastEvent = FireEvent(date: clock.now, result: .failure(message: error.userMessage))
            if !manual { notifier.notifyFailure(message: error.userMessage) }
        }
    }
}
