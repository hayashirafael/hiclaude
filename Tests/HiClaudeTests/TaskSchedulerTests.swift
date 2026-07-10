import XCTest
@testable import HiClaude

@MainActor
final class TaskSchedulerTests: XCTestCase {
    // FakeClock mutável, no padrão dos testes existentes (FireControllerTests).
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

    private func task(times: [Int], weekdays: Set<Int> = Set(1...7),
                      enabled: Bool = true) -> ScheduledTask {
        ScheduledTask(uid: UUID(), name: nil, commandUID: nil,
                      times: times, weekdays: weekdays, enabled: enabled)
    }

    func testConfigureArmaProximaOcorrenciaSemDispararNoLaunch() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var fired: [UUID] = []
        scheduler.onFire = { fired.append($0.uid); return true }
        let t = task(times: [480]) // 08:00
        await scheduler.configure(tasks: [t], paused: false)
        XCTAssertEqual(scheduler.nextFires[t.uid], date(2026, 7, 9, 8, 0))
        XCTAssertTrue(fired.isEmpty) // launch não dispara retroativo
    }

    func testWakeAposHorarioPerdidoDispara() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var fired: [UUID] = []
        scheduler.onFire = { fired.append($0.uid); return true }
        let t = task(times: [480])
        await scheduler.configure(tasks: [t], paused: false)
        clock.now = date(2026, 7, 9, 9, 0) // dormiu através das 08:00
        await scheduler.handleWake()
        XCTAssertEqual(fired, [t.uid])
        // encadeia: próxima é amanhã 08:00
        XCTAssertEqual(scheduler.nextFires[t.uid], date(2026, 7, 10, 8, 0))
    }

    func testDedupeNaoDisparaDuasVezesEmSeguida() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var count = 0
        scheduler.onFire = { _ in count += 1; return true }
        let t = task(times: [480])
        await scheduler.configure(tasks: [t], paused: false)
        clock.now = date(2026, 7, 9, 8, 1)
        await scheduler.handleWake()
        await scheduler.handleWake() // segundo wake 0s depois → dedupe
        XCTAssertEqual(count, 1)
    }

    func testPausaLimpaTimersEStatus() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        let t = task(times: [480])
        await scheduler.configure(tasks: [t], paused: false)
        await scheduler.configure(tasks: [t], paused: true)
        XCTAssertTrue(scheduler.nextFires.isEmpty)
    }

    func testTarefaDesabilitadaNaoArma() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        let t = task(times: [480], enabled: false)
        await scheduler.configure(tasks: [t], paused: false)
        XCTAssertNil(scheduler.nextFires[t.uid])
    }

    func testEditarTarefaArmadaReArmaParaNovoHorario() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var fired: [UUID] = []
        scheduler.onFire = { fired.append($0.uid); return true }
        let uid = UUID()
        let original = ScheduledTask(uid: uid, name: nil, commandUID: nil,
                                     times: [480], weekdays: Set(1...7), enabled: true) // 08:00
        await scheduler.configure(tasks: [original], paused: false)
        XCTAssertEqual(scheduler.nextFires[uid], date(2026, 7, 9, 8, 0))

        // Usuário edita para 09:00 enquanto ainda armado para 08:00.
        let edited = ScheduledTask(uid: uid, name: nil, commandUID: nil,
                                   times: [540], weekdays: Set(1...7), enabled: true) // 09:00
        await scheduler.configure(tasks: [edited], paused: false)
        XCTAssertEqual(scheduler.nextFires[uid], date(2026, 7, 9, 9, 0))

        clock.now = date(2026, 7, 9, 8, 0) // horário antigo, removido pela edição
        await scheduler.handleWake()
        XCTAssertTrue(fired.isEmpty)

        clock.now = date(2026, 7, 9, 9, 0)
        await scheduler.handleWake()
        XCTAssertEqual(fired, [uid])
    }

    func testEdicaoNaoDisparaCatchUpRetroativoDoNovoHorario() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var fired: [UUID] = []
        scheduler.onFire = { fired.append($0.uid); return true }
        let uid = UUID()
        let original = ScheduledTask(uid: uid, name: nil, commandUID: nil,
                                     times: [1320], weekdays: Set(1...7), enabled: true) // 22:00
        await scheduler.configure(tasks: [original], paused: false)

        clock.now = date(2026, 7, 9, 7, 31)
        // Edita para 07:15 — já ficou "no passado" no exato momento da edição.
        let edited = ScheduledTask(uid: uid, name: nil, commandUID: nil,
                                   times: [435], weekdays: Set(1...7), enabled: true) // 07:15
        await scheduler.configure(tasks: [edited], paused: false)
        XCTAssertTrue(fired.isEmpty) // edição não é catch-up retroativo

        clock.now = date(2026, 7, 10, 7, 15) // ocorrência real de amanhã
        await scheduler.handleWake()
        XCTAssertEqual(fired, [uid])
    }

    func testDedupePorLastFireAtBloqueiaSegundoFireDentroDoIntervalo() async {
        // Cobre o branch `if let last = lastFireAt[...], now.timeIntervalSince(last) < dedupeInterval`
        // em fire(), chegando por um caminho que NÃO passa pelo guard
        // "armed no futuro" do rearm (esse guard intercepta o teste de
        // dedupe existente antes mesmo de chamar fire()).
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var count = 0
        scheduler.onFire = { _ in count += 1; return true }
        // Dois horários no mesmo dia a 60s um do outro — bem dentro da janela
        // de dedupe de 120s.
        let t = task(times: [480, 481]) // 08:00 e 08:01
        await scheduler.configure(tasks: [t], paused: false)

        clock.now = date(2026, 7, 9, 8, 0) // == armado: cai no guard "armed <= now", não no de futuro
        await scheduler.handleWake() // dispara 08:00; encadeia para 08:01 (mesmo dia)
        XCTAssertEqual(count, 1)

        clock.now = date(2026, 7, 9, 8, 1) // == novo armado, 60s depois do fire anterior
        await scheduler.handleWake() // também cai no guard "armed <= now" (não no de futuro) → chama fire()
        XCTAssertEqual(count, 1) // dedupe por lastFireAt bloqueia dentro de fire(), sem novo onFire
    }

    func testFireDescartadoPeloGuardEntraEmRetry() async {
        let clock = MutableClock(date(2026, 7, 9, 7, 0))
        let scheduler = TaskScheduler(clock: clock, calendar: cal)
        var results: [Bool] = [false, true] // 1ª tentativa descartada, 2ª executa
        var count = 0
        scheduler.onFire = { _ in count += 1; return results.removeFirst() }
        let t = task(times: [480])
        await scheduler.configure(tasks: [t], paused: false)
        clock.now = date(2026, 7, 9, 8, 1)
        await scheduler.handleWake()   // dispara, é descartado → pendingRetry
        clock.now = date(2026, 7, 9, 8, 2)
        await scheduler.rearmAll()     // retry executa
        XCTAssertEqual(count, 2)
    }
}
