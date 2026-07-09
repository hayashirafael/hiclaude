import AppKit
import Combine
import Foundation

/// Composição: cria as unidades, liga o engine ao controller e observa
/// wake do sleep e mudança do relógio do sistema.
@MainActor
final class AppEnvironment: ObservableObject {
    let state: AppState
    private let engine: SchedulerEngine
    private var controller: FireController
    private let detector: SessionDetector
    private let renewalEngine: RenewalEngine
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var statusTimer: Timer?

    init() {
        let state = AppState()
        let detector = SessionDetector()
        self.state = state
        self.detector = detector
        self.engine = SchedulerEngine(lastCheck: state.lastCheck)
        self.controller = FireController(state: state, detector: detector,
                                         runner: ClaudeRunner(configDir: state.resolvedConfigDir),
                                         notifier: SystemNotifier())
        self.renewalEngine = RenewalEngine(detector: detector)

        engine.onFire = { [weak self] minutes in
            Task { @MainActor in await self?.scheduledFire(minutes: minutes) }
        }

        renewalEngine.onRenew = { [weak self] account in
            guard let self else { return }
            // Renovação = ping mínimo (1+1 default) fixado na conta a renovar.
            var msg = AppState.defaultMessage
            msg.configDir = account.path
            await self.controller.fire(message: msg, origin: .renewal)
        }
        renewalEngine.onStatus = { [weak self] next in
            self?.state.nextRenewals = next
        }

        // Sonda do CLI fora da thread principal: quando `claude` não está nos
        // candidatos padrão, `locateClaude()` faz spawn de um shell de login
        // (`command -v claude`) — um stall real no launch. `claudeFound` já
        // começa `true`, então o ícone de erro não pisca enquanto isso resolve.
        Task.detached {
            let found = ClaudeRunner.locateClaude() != nil
            await MainActor.run { state.claudeFound = found }
        }
        reconfigure()
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

        Task { @MainActor [weak self] in await self?.refreshWindowStatus() }

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.statusTick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        statusTimer = timer

        // Trocar de conta global (menu ou janela) recompõe o runner (fallback de
        // conta) e reflete a janela na UI. `dropFirst` ignora o valor inicial.
        state.$claudeConfigDir
            .dropFirst()
            .sink { [weak self] _ in self?.reconfigureAccount() }
            .store(in: &cancellables)

        // Trocar a mensagem ativa pode mudar a conta efetiva alvo — reflete a
        // janela dessa conta na UI.
        state.$activeMessage
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refreshWindowStatus() }
            }
            .store(in: &cancellables)

        // Ligar/desligar renovação por conta reconfigura o engine.
        state.$renewAccounts
            .dropFirst()
            .sink { [weak self] _ in self?.reconfigureRenewals() }
            .store(in: &cancellables)
        reconfigureRenewals()
    }

    var nextFire: (date: Date, minutes: Int)? { engine.nextFire }

    func reconfigure() {
        engine.configure(times: state.times, paused: state.paused)
    }

    func togglePause() {
        state.paused.toggle()
        reconfigure()
        reconfigureRenewals() // pausar suspende as renovações também
    }

    /// Reconfigura o RenewalEngine com as contas marcadas que ainda existem.
    private func reconfigureRenewals() {
        let accounts = state.renewAccounts
            .map { URL(fileURLWithPath: $0) }
            .filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    && isDir.boolValue
            }
        let paused = state.paused
        Task { @MainActor [weak self] in
            await self?.renewalEngine.configure(accounts: accounts, paused: paused)
        }
    }

    func setActiveMessage(_ message: Message) {
        state.setActiveMessage(message)
    }

    func setAccount(_ url: URL) {
        state.setAccount(url)
    }

    /// Recompõe o runner a partir da conta global (fallback de conta das
    /// mensagens sem override) e reflete a janela na UI. O detector é stateless
    /// quanto à conta — recebe o `projectsDir` por chamada. Disparado pela
    /// observação de `claudeConfigDir`.
    private func reconfigureAccount() {
        let dir = state.resolvedConfigDir
        controller = FireController(state: state, detector: detector,
                                    runner: ClaudeRunner(configDir: dir),
                                    notifier: SystemNotifier())
        Task { @MainActor [weak self] in await self?.refreshWindowStatus() }
    }

    func fireNow() async {
        await controller.fire(message: state.resolvedMessage, origin: .manual)
        await renewalEngine.rearmAll() // o hi pode ter aberto janela → arma a renovação
    }

    /// Tick periódico: re-detecta a janela ativa (alimenta ícone e "3h12").
    func statusTick() async {
        await refreshWindowStatus()
        await renewalEngine.rearmAll() // arma contas que ganharam janela por fora
    }

    func refreshWindowStatus() async {
        // Reflete a janela da conta que será de fato aquecida (a da mensagem ativa).
        let projects = state.effectiveConfigDir(for: state.resolvedMessage)
            .appendingPathComponent("projects")
        state.activeWindowEnd = await detector.activeWindowEnd(projectsDir: projects)
    }

    private func scheduledFire(minutes: Int) async {
        await controller.fire(message: state.resolvedMessage(forMinutes: minutes),
                              origin: .scheduled)
        persistLastCheck()
        await renewalEngine.rearmAll()
    }

    private func handleWake() {
        engine.handleWake()
        persistLastCheck()
        Task { @MainActor [weak self] in await self?.renewalEngine.handleWake() }
    }

    /// lastCheck persistido a cada evento; se o app morrer sem salvar, o
    /// catch-up seguinte pode disparar redundante — e o detector pula. Auto-corrige.
    private func persistLastCheck() {
        state.lastCheck = engine.lastCheck
    }
}
