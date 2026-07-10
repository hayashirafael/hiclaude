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
            guard let self,
                  let task = self.state.tasks.first(where: {
                      $0.enabled && $0.repetition == .continuous
                          && self.state.accountDir(for: $0) == account
                  }) else { return true }
            return await self.controller.fire(message: task.resolvedCommand, origin: .renewal)
        }
        renewalEngine.onStatus = { [weak self] next in
            self?.state.nextRenewals = next
        }

        taskScheduler.onFire = { [weak self] task in
            guard let self else { return false }
            let cmd = task.resolvedCommand
            // Conta explícita cuja pasta sumiu: não dispara (cairia na conta
            // padrão errada); registra a falha para a UI avisar.
            if cmd.kind != .shell, let path = cmd.configDir, !path.isEmpty,
               self.state.accountDir(for: task) == nil {
                self.state.recordEvent(FireEvent(
                    date: Date(), result: .failure(message: "pasta da conta não encontrada"),
                    messageText: cmd.text,
                    account: URL(fileURLWithPath: path).lastPathComponent,
                    origin: .agenda))
                return true
            }
            return await self.controller.fire(message: cmd, origin: .agenda)
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

        // Editar a lista de agendamentos reconfigura os dois motores.
        state.$tasks
            .dropFirst()
            .sink { [weak self] _ in self?.reconfigureSchedules() }
            .store(in: &cancellables)
        reconfigureSchedules()
    }

    func togglePause() {
        state.paused.toggle()
        reconfigureSchedules()
    }

    /// Reconfigura os dois motores a partir da lista unificada: contínuos
    /// alimentam o RenewalEngine (por conta), fixos o TaskScheduler.
    private func reconfigureSchedules() {
        var accounts: Set<URL> = []
        for task in state.tasks where task.enabled && task.repetition == .continuous {
            if let dir = state.accountDir(for: task) { accounts.insert(dir) }
        }
        let fixed = state.tasks.filter { $0.repetition == .fixed }
        let paused = state.paused
        Task { @MainActor [weak self] in
            await self?.renewalEngine.configure(accounts: accounts, paused: paused)
            await self?.taskScheduler.configure(tasks: fixed, paused: paused)
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
