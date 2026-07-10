import XCTest
@testable import HiClaude

/// Regressão do bug "um passo atrás": `@Published` publica no willSet, então
/// o sink de `$tasks` NÃO pode ler `state.tasks` sincronamente — leria a
/// lista antiga e reconfiguraria os motores sem a mudança recém-feita.
@MainActor
final class AppEnvironmentTests: XCTestCase {
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

    // NOTA de isolamento: este teste usa o `AppEnvironment` de produção, cujo
    // `TaskScheduler` está ligado ao `FireController`/`TerminalLauncher` REAIS.
    // O `armTimer` agenda um `NSTimer` REAL no RunLoop.main. Se a data alvo já
    // passou (clock fake no passado), o timer nasce vencido e dispara em algum
    // `await` — chamando `TerminalLauncher.launch` → `NSAppleScript` real, que
    // ABRE UM TERMINAL de verdade (e crasha/falha a run, de forma flaky e
    // dependente da data de hoje). Por isso os testes usam datas bem no FUTURO
    // (ano 2099): o timer arma mas nunca vence durante a suíte, então nenhum
    // efeito colateral real acontece. O `tearDown` abaixo é defesa em
    // profundidade: pausa o scheduler para invalidar qualquer timer remanescente.
    private var activeScheduler: TaskScheduler?

    override func tearDown() async throws {
        await activeScheduler?.configure(tasks: [], paused: true)
        activeScheduler = nil
        try await super.tearDown()
    }

    private func makeEnv(clock: MutableClock) -> (AppEnvironment, AppState, TaskScheduler) {
        let state = AppState(defaults: freshDefaults())
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        let env = AppEnvironment(state: state, taskScheduler: scheduler, probeCLIs: false)
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
}
