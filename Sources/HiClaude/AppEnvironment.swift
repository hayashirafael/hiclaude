import AppKit
import Combine
import Foundation

/// Composição: cria as unidades, liga o engine ao controller e observa
/// wake do sleep e mudança do relógio do sistema.
@MainActor
final class AppEnvironment: ObservableObject {
    let state: AppState
    private let controller: FireController
    private let detector: SessionDetector
    private let renewalEngine: RenewalEngine
    private let taskScheduler: TaskScheduler
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var statusTimer: Timer?

    init() {
        let state = AppState()
        let detector = SessionDetector()
        self.state = state
        self.detector = detector
        self.controller = FireController(state: state, detector: detector,
                                         runner: CommandRunner(configDir: AppState.defaultConfigDir),
                                         notifier: SystemNotifier())
        self.renewalEngine = RenewalEngine(detector: detector)
        self.taskScheduler = TaskScheduler()

        renewalEngine.onRenew = { [weak self] account in
            guard let self else { return false }
            var msg = self.state.resolvedRenewalMessage(for: account)
            msg.configDir = account.path
            return await self.controller.fire(message: msg, origin: .renewal)
        }
        renewalEngine.onStatus = { [weak self] next in
            self?.state.nextRenewals = next
        }

        taskScheduler.onFire = { [weak self] task in
            guard let self else { return false }
            let msg = self.state.resolvedTaskMessage(for: task)
            return await self.controller.fire(message: msg, origin: .agenda)
        }
        taskScheduler.onStatus = { [weak self] next in
            self?.state.nextTaskFires = next
        }

        // Sonda dos CLIs fora da thread principal: quando `claude`/`codex` não
        // estão nos candidatos padrão, `locate()` faz spawn de um shell de
        // login (`command -v ...`) — um stall real no launch. `cliFound` já
        // começa `true` para os dois, então o ícone de erro não pisca enquanto
        // isso resolve.
        Task.detached {
            let claude = CommandRunner.locate(.claude) != nil
            let codex = CommandRunner.locate(.codex) != nil
            await MainActor.run {
                state.cliFound[.claude] = claude
                state.cliFound[.codex] = codex
            }
        }
        handleWake() // catch-up do boot via mesmo caminho do wake/clock-change

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleWake() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleWake() }
        })

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.statusTick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        statusTimer = timer

        // Ligar/desligar renovação por conta reconfigura o engine.
        state.$renewals
            .dropFirst()
            .sink { [weak self] _ in self?.reconfigureRenewals() }
            .store(in: &cancellables)
        reconfigureRenewals()

        // Ligar/desligar tarefas ou editar a agenda reconfigura o scheduler.
        state.$tasks
            .dropFirst()
            .sink { [weak self] _ in self?.reconfigureTasks() }
            .store(in: &cancellables)
        reconfigureTasks()
    }

    func togglePause() {
        state.paused.toggle()
        reconfigureRenewals()
        reconfigureTasks()
    }

    /// Reconfigura o RenewalEngine com as contas em renovação que ainda existem.
    private func reconfigureRenewals() {
        var configs: [URL: AccountRenewal] = [:]
        for (path, config) in state.renewals {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                configs[url.standardizedFileURL] = config
            }
        }
        let paused = state.paused
        Task { @MainActor [weak self] in
            await self?.renewalEngine.configure(renewals: configs, paused: paused)
        }
    }

    /// Reconfigura o TaskScheduler com as tarefas atuais.
    private func reconfigureTasks() {
        let tasks = state.tasks
        let paused = state.paused
        Task { @MainActor [weak self] in
            await self?.taskScheduler.configure(tasks: tasks, paused: paused)
        }
    }

    /// Tick periódico: re-arma as renovações e a agenda (alimenta ícone e "3h12" na barra).
    func statusTick() async {
        await renewalEngine.rearmAll()
        await taskScheduler.rearmAll()
    }

    private func handleWake() {
        Task { @MainActor [weak self] in
            await self?.renewalEngine.handleWake()
            await self?.taskScheduler.handleWake()
        }
    }
}
