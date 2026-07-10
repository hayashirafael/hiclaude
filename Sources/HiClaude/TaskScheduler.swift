import Foundation

/// Dispara tarefas da agenda em horários fixos × dias da semana. Espelho do
/// padrão do RenewalEngine: timers reais só no app; catch-up de sleep testado
/// com relógio fake. O skip por sessão ativa acontece no FireController.
@MainActor
final class TaskScheduler {
    /// Retorna `true` quando o disparo executou e `false` quando foi
    /// descartado pelo guard `isRunning` do controller — nesse caso fica em
    /// retry para a próxima chamada (statusTick, wake, outro fire).
    var onFire: ((ScheduledTask) async -> Bool)?
    /// Snapshot de `nextFires` a cada mudança — vira "próxima qua 08:00" na UI.
    var onStatus: (([UUID: Date]) -> Void)?

    private(set) var nextFires: [UUID: Date] = [:] {
        didSet { onStatus?(nextFires) }
    }

    private let clock: Clock
    private let calendar: Calendar
    private let dedupeInterval: TimeInterval = 120
    private var tasks: [UUID: ScheduledTask] = [:]
    private var paused = false
    private var timers: [UUID: Timer] = [:]
    private var lastFireAt: [UUID: Date] = [:]
    private var pendingRetry: Set<UUID> = []
    /// Launch não dispara catch-up: só ocorrências perdidas depois disso contam.
    private let startedAt: Date

    init(clock: Clock = SystemClock(), calendar: Calendar = .current) {
        self.clock = clock
        self.calendar = calendar
        self.startedAt = clock.now
    }

    func configure(tasks list: [ScheduledTask], paused: Bool) async {
        let previousTasks = tasks
        var normalized: [UUID: ScheduledTask] = [:]
        for task in list where task.enabled { normalized[task.uid] = task }
        self.tasks = normalized
        self.paused = paused
        for uid in Array(timers.keys) where paused || normalized[uid] == nil {
            timers[uid]?.invalidate()
            timers[uid] = nil
        }
        if paused {
            nextFires = [:]
            pendingRetry.removeAll()
        } else {
            for uid in Array(nextFires.keys) where normalized[uid] == nil {
                nextFires[uid] = nil
            }
            pendingRetry = pendingRetry.filter { normalized[$0] != nil }
            // Uid presente antes e depois, mas com conteúdo diferente (ex.:
            // horário editado): o timer armado aponta para o horário ANTIGO.
            // Sem isso, `rearm` vê `armed > now` com timer vivo e devolve
            // cedo — a tarefa dispararia no horário que o usuário removeu.
            // Invalida só os uids realmente editados (não todo mundo a cada
            // publish de `$tasks`, o que re-armaria timers não relacionados).
            for (uid, newTask) in normalized {
                guard let old = previousTasks[uid], old != newTask else { continue }
                timers[uid]?.invalidate()
                timers[uid] = nil
                nextFires[uid] = nil
                // Avança o piso do catch-up para agora: sem isso, o rearm
                // poderia achar uma ocorrência do NOVO horário perdida entre
                // o último disparo real e o momento da edição, e disparar na
                // hora algo que o usuário acabou de configurar (catch-up
                // retroativo indesejado). Efeito colateral aceito: uma
                // segunda edição da MESMA tarefa dentro dos 120s seguintes
                // não é bloqueada pelo dedupe de `fire()` (que só olha
                // disparos reais) — editar não é disparar, então não há
                // nada para dedupar.
                lastFireAt[uid] = clock.now
            }
        }
        await rearmAll()
    }

    /// Chamar ao acordar do sleep — e após cada disparo.
    func handleWake() async { await rearmAll() }

    func rearmAll() async {
        guard !paused else { return }
        for uid in Array(tasks.keys) { await rearm(uid) }
    }

    private func rearm(_ uid: UUID) async {
        guard let task = tasks[uid] else { return }
        if pendingRetry.contains(uid) {
            pendingRetry.remove(uid)
            await fire(task)
            return
        }
        if let armed = nextFires[uid], armed > clock.now, timers[uid] != nil { return }
        // Armado que passou (sleep engoliu o timer) → dispara já; o skip por
        // sessão ativa fica a cargo do FireController.
        if let armed = nextFires[uid], armed <= clock.now {
            timers[uid]?.invalidate(); timers[uid] = nil
            nextFires[uid] = nil
            await fire(task)
            return
        }
        // Sem armado: ocorrência perdida desde o último disparo (nunca antes
        // do launch) → catch-up único.
        let since = max(lastFireAt[uid] ?? startedAt, startedAt)
        if AgendaMath.lastMissedOccurrence(times: task.times, weekdays: task.weekdays,
                                           between: since, and: clock.now,
                                           calendar: calendar) != nil {
            await fire(task)
            return
        }
        guard let next = AgendaMath.nextOccurrence(times: task.times, weekdays: task.weekdays,
                                                   after: clock.now, calendar: calendar)
        else { return }
        armTimer(uid, at: next)
    }

    private func armTimer(_ uid: UUID, at date: Date) {
        nextFires[uid] = date
        timers[uid]?.invalidate()
        let t = Timer(fire: date.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.timers[uid] = nil
                if let task = self.tasks[uid] { await self.fire(task) }
            }
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timers[uid] = t
    }

    private func fire(_ task: ScheduledTask) async {
        guard !paused, tasks[task.uid] != nil else {
            pendingRetry.remove(task.uid)
            return
        }
        let now = clock.now
        if let last = lastFireAt[task.uid], now.timeIntervalSince(last) < dedupeInterval { return }
        nextFires[task.uid] = nil
        let didRun = await onFire?(task) ?? true
        guard didRun else {
            pendingRetry.insert(task.uid)
            return
        }
        pendingRetry.remove(task.uid)
        lastFireAt[task.uid] = now
        await rearm(task.uid) // encadeia a próxima ocorrência
    }
}
