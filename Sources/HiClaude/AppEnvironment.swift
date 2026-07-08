import AppKit
import Foundation

/// Composição: cria as unidades, liga o engine ao controller e observa
/// wake do sleep e mudança do relógio do sistema.
@MainActor
final class AppEnvironment: ObservableObject {
    let state: AppState
    private let engine: SchedulerEngine
    private let controller: FireController
    private let detector: SessionDetector
    private var observers: [NSObjectProtocol] = []

    init() {
        let state = AppState()
        let detector = SessionDetector()
        self.state = state
        self.detector = detector
        self.engine = SchedulerEngine(lastCheck: state.lastCheck)
        self.controller = FireController(state: state, detector: detector,
                                         runner: ClaudeRunner(), notifier: NullNotifier())

        engine.onFire = { [weak self] in
            Task { @MainActor in await self?.scheduledFire() }
        }

        state.claudeFound = ClaudeRunner.locateClaude() != nil
        reconfigure()
        engine.handleWake() // catch-up do boot (lastCheck persistido da execução anterior)
        persistLastCheck()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        })

        Task { @MainActor [weak self] in await self?.refreshWindowStatus() }
    }

    var nextFireDate: Date? { engine.nextFireDate }

    func reconfigure() {
        engine.configure(times: state.times, paused: state.paused)
    }

    func togglePause() {
        state.paused.toggle()
        reconfigure()
    }

    func fireNow() async {
        await controller.fire(manual: true)
    }

    func refreshWindowStatus() async {
        state.activeWindowEnd = await detector.activeWindowEnd()
    }

    private func scheduledFire() async {
        await controller.fire(manual: false)
        persistLastCheck()
    }

    private func handleWake() {
        engine.handleWake()
        persistLastCheck()
    }

    /// lastCheck persistido a cada evento; se o app morrer sem salvar, o
    /// catch-up seguinte pode disparar redundante — e o detector pula. Auto-corrige.
    private func persistLastCheck() {
        state.lastCheck = engine.lastCheck
    }
}
