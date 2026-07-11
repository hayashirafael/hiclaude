import XCTest
@testable import HiClaude

/// Regressão do bug "um passo atrás": `@Published` publica no willSet, então
/// o sink de `$tasks` NÃO pode ler `state.tasks` sincronamente — leria a
/// lista antiga e reconfiguraria os motores sem a mudança recém-feita.
@MainActor
final class AppEnvironmentTests: XCTestCase {
    private struct NoopTerminalLauncher: TerminalLaunching {
        func launch(_ message: Message) async -> Result<Void, RunnerError> { .success(()) }
    }

    private final class MutableClock: Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "hiclaude-test-\(UUID().uuidString)")!
        d.set([String](), forKey: "registeredAccounts")
        return d
    }

    // O scheduler usa NSTimer real, mas o launcher é fake: mesmo uma data fake
    // vencida nunca abre Terminal.app durante a suíte.
    private var activeScheduler: TaskScheduler?

    override func tearDown() async throws {
        await activeScheduler?.configure(tasks: [], paused: true)
        activeScheduler = nil
        try await super.tearDown()
    }

    private func makeEnv(clock: MutableClock) -> (AppEnvironment, AppState, TaskScheduler) {
        let state = AppState(defaults: freshDefaults())
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        let env = AppEnvironment(state: state, taskScheduler: scheduler,
                                 terminalLauncher: NoopTerminalLauncher(), probeCLIs: false)
        activeScheduler = scheduler
        return (env, state, scheduler)
    }

    private func fixedTask(times: [Int]) -> ScheduledTask {
        ScheduledTask(uid: UUID(), repetition: .fixed, times: times, weekdays: Set(1...7))
    }

    private func drain(_ env: AppEnvironment) async {
        await env.reconfigureTask?.value
    }

    func testCriarTarefaRefleteNoSchedulerImediatamente() async {
        let clock = MutableClock(date(2099, 7, 9, 12, 40))
        let (env, state, scheduler) = makeEnv(clock: clock)
        await drain(env)

        let t = fixedTask(times: [764]) // 12:44
        state.tasks.append(t)
        await drain(env)

        XCTAssertEqual(scheduler.nextFires[t.uid], date(2099, 7, 9, 12, 44))
    }

    func testEditarTarefaAplicaOConteudoNovoNaoOAnterior() async {
        let clock = MutableClock(date(2099, 7, 9, 12, 40))
        let (env, state, scheduler) = makeEnv(clock: clock)
        let t = fixedTask(times: [764]) // 12:44
        state.tasks.append(t)
        await drain(env)

        var editada = t
        editada.times = [770] // 12:50
        state.tasks[0] = editada
        await drain(env)

        XCTAssertEqual(scheduler.nextFires[t.uid], date(2099, 7, 9, 12, 50))
    }

    func testRemoverTarefaSaiDoScheduler() async {
        let clock = MutableClock(date(2099, 7, 9, 12, 40))
        let (env, state, scheduler) = makeEnv(clock: clock)
        let t = fixedTask(times: [764])
        state.tasks.append(t)
        await drain(env)
        XCTAssertNotNil(scheduler.nextFires[t.uid])

        state.tasks.removeAll { $0.uid == t.uid }
        await drain(env)

        XCTAssertNil(scheduler.nextFires[t.uid])
    }

    /// Regressão do bug "menu não atualiza a próxima schedule": o tick periódico
    /// precisa publicar uma mudança em `AppState` para o menu (que lê horários
    /// via `Date()` em computed properties) recomputar. Sem o pulso, `rearmAll`
    /// faz early-return sem mutar nada e o `objectWillChange` nunca dispara.
    func testStatusTickPublicaPulsoDeUI() async {
        let clock = MutableClock(date(2099, 7, 9, 12, 40))
        let (env, state, _) = makeEnv(clock: clock)
        await drain(env)

        let antes = state.uiHeartbeat
        await env.statusTick()

        XCTAssertNotEqual(state.uiHeartbeat, antes)
    }

    func testRefreshWindowEndsPublicaFimDeJanelaPorContaAgendada() async {
        let defaults = UserDefaults(suiteName: "hiclaude-test-\(UUID().uuidString)")!
        let state = AppState(defaults: defaults)
        var task = ScheduledTask(uid: UUID(), command: AppState.defaultMessage)
        task.repetition = .fixed // sem times: nenhum timer arma
        state.tasks = [task]
        let detector = MockDetector()
        let end = Date().addingTimeInterval(3600)
        detector.end = end
        let env = AppEnvironment(state: state, taskScheduler: TaskScheduler(),
                                 detector: detector, probeCLIs: false)
        await env.refreshWindowEnds()
        XCTAssertEqual(state.windowEnds[AppState.defaultConfigDir.standardizedFileURL], end)

        // Janela que sumiu (nil) sai do dicionário no próximo refresh.
        detector.end = nil
        await env.refreshWindowEnds()
        XCTAssertTrue(state.windowEnds.isEmpty)
    }
}
