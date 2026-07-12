import Foundation

/// Linha da lista de Horários já resolvida contra o AppState: a view monta as
/// linhas (paths, rótulos e próximos disparos) e o modelo — puro — filtra,
/// ordena e resume.
struct HorariosRow: Equatable {
    let task: ScheduledTask
    /// Path padronizado da conta mirada; nil para shell ou pasta sumida.
    let accountPath: String?
    /// Rótulo da conta (apelido → e-mail → pasta); nil para shell.
    let accountLabel: String?
    /// Próximo disparo futuro; nil quando desativada ou nada armado.
    let nextFire: Date?
}

/// Filtro da lista — nil em uma dimensão = dimensão sem filtro.
struct HorariosFilter: Equatable {
    var accountPath: String? = nil
    var kind: Message.Kind? = nil
    var enabled: Bool? = nil
    var repetition: ScheduledTask.Repetition? = nil

    var isActive: Bool {
        accountPath != nil || kind != nil || enabled != nil || repetition != nil
    }
}

/// Critérios do menu "Ordenar" — padrão é a ordem de criação da lista.
enum HorariosSort: String, CaseIterable {
    case padrao, conta, proximoDisparo, nome
}

/// Resumo da barra do topo: contagens do total e próximo disparo entre ativas.
struct HorariosSummary: Equatable {
    let total: Int
    let active: Int
    let next: Date?
}

/// Filtro, ordenação e resumo da tela Horários — funções puras, testáveis.
enum HorariosListModel {
    /// Título exibido: nome do agendamento, senão o texto do comando.
    static func title(_ task: ScheduledTask) -> String {
        task.name ?? task.resolvedCommand.text
    }

    static func apply(_ rows: [HorariosRow], filter: HorariosFilter,
                      sort: HorariosSort) -> [HorariosRow] {
        sorted(filtered(rows, filter: filter), by: sort)
    }

    static func summary(_ rows: [HorariosRow]) -> HorariosSummary {
        let active = rows.filter { $0.task.enabled }
        return HorariosSummary(total: rows.count, active: active.count,
                               next: active.compactMap(\.nextFire).min())
    }

    private static func filtered(_ rows: [HorariosRow],
                                 filter: HorariosFilter) -> [HorariosRow] {
        rows.filter { row in
            if let path = filter.accountPath, row.accountPath != path { return false }
            if let kind = filter.kind, row.task.resolvedCommand.kind != kind { return false }
            if let enabled = filter.enabled, row.task.enabled != enabled { return false }
            if let repetition = filter.repetition, row.task.repetition != repetition {
                return false
            }
            return true
        }
    }

    /// Ordenação estável: `sort(by:)` do Swift não garante estabilidade, então
    /// o desempate é sempre a posição original (= ordem de criação).
    private static func sorted(_ rows: [HorariosRow],
                               by sort: HorariosSort) -> [HorariosRow] {
        guard sort != .padrao else { return rows }
        return rows.enumerated().sorted { a, b in
            switch compare(a.element, b.element, by: sort) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.offset < b.offset
            }
        }.map(\.element)
    }

    private static func compare(_ a: HorariosRow, _ b: HorariosRow,
                                by sort: HorariosSort) -> ComparisonResult {
        switch sort {
        case .padrao:
            return .orderedSame
        case .conta:
            // Sem conta (shell/pasta sumida) vai para o fim.
            switch (a.accountLabel, b.accountLabel) {
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            case let (la?, lb?): return la.localizedCaseInsensitiveCompare(lb)
            }
        case .proximoDisparo:
            // Sem próximo disparo (desativada ou nada armado) vai para o fim.
            switch (a.nextFire, b.nextFire) {
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            case let (da?, db?):
                if da == db { return .orderedSame }
                return da < db ? .orderedAscending : .orderedDescending
            }
        case .nome:
            return title(a.task).localizedCaseInsensitiveCompare(title(b.task))
        }
    }
}
