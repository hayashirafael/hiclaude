import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case portuguese = "pt-BR"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: return "en_US"
        case .portuguese: return "pt_BR"
        }
    }

    var pickerTitle: String {
        switch self {
        case .english: return "English"
        case .portuguese: return "Português"
        }
    }
}

struct L10n {
    let language: AppLanguage

    var settingsTitle: String { text(en: "Settings", pt: "Configurações") }
    var accounts: String { text(en: "Accounts", pt: "Contas") }
    var schedules: String { text(en: "Schedules", pt: "Horários") }
    var history: String { text(en: "History", pt: "Histórico") }
    /// Chip de filtro por conta (deep-link do painel) nas abas Tarefas/Histórico.
    func filteredBy(_ label: String) -> String {
        text(en: "Filtered: \(label)", pt: "Filtrando: \(label)")
    }
    var clearFilter: String { text(en: "Clear filter", pt: "Limpar filtro") }
    var general: String { text(en: "General", pt: "Geral") }
    var command: String { text(en: "Command", pt: "Comando") }
    var paused: String { text(en: "Paused", pt: "Pausado") }
    var pause: String { text(en: "Pause", pt: "Pausar") }
    var resume: String { text(en: "Resume", pt: "Retomar") }
    var quit: String { text(en: "Quit", pt: "Sair") }
    var add: String { text(en: "Add", pt: "Adicionar") }
    var save: String { text(en: "Save", pt: "Salvar") }
    var cancel: String { text(en: "Cancel", pt: "Cancelar") }
    var ok: String { "OK" }
    var enabled: String { text(en: "Enabled", pt: "Habilitado") }
    var languageLabel: String { text(en: "Language", pt: "Idioma") }
    var launchAtLogin: String { text(en: "Launch at Login", pt: "Iniciar com o Mac") }
    var remainingInMenuBar: String { text(en: "Remaining time in menu bar", pt: "Tempo restante na barra") }
    var version: String { text(en: "Version", pt: "Versão") }
    var remainingInMenuBarFooter: String {
        text(en: "The menu bar time shows the first account renewal window to expire.",
             pt: "O tempo na barra mostra a janela que vence primeiro entre as contas em renovação.")
    }

    func settingsSectionTitle(_ section: SettingsSection) -> String {
        switch section {
        case .contas: return accounts
        case .horarios: return schedules
        case .historico: return history
        case .geral: return general
        }
    }

    func cliNotFound(_ provider: Provider) -> String {
        text(en: "\(provider.displayName) CLI not found",
             pt: "CLI do \(provider.displayName) não encontrado")
    }

    func installCLIWarning(_ provider: Provider) -> String {
        let cliName = provider == .claude ? "Claude Code" : "Codex CLI"
        return text(en: "\(provider.displayName) CLI not found - install \(cliName)",
                    pt: "CLI do \(provider.displayName) não encontrado — instale o \(cliName)")
    }

    func installCLIForAccount(_ provider: Provider) -> String {
        text(en: "\(provider.displayName) CLI not found - install it to run this account",
             pt: "CLI do \(provider.displayName) não encontrado — instale para disparar nesta conta")
    }

    var commandTimeout: String {
        text(en: "the command did not respond within 60s",
             pt: "o comando não respondeu em 60s")
    }

    var accountFolderMissing: String {
        text(en: "account folder not found - the schedule will not run",
             pt: "pasta da conta não encontrada — o agendamento não dispara")
    }

    var accountFolderMissingEvent: String {
        text(en: "account folder not found",
             pt: "pasta da conta não encontrada")
    }

    var accountFolderMissingAccountTab: String {
        text(en: "folder not found - remove it from the list or restore the folder",
             pt: "pasta não encontrada — remova da lista ou restaure a pasta")
    }

    var providerLabel: String { text(en: "Provider", pt: "Provedor") }
    var folderLabel: String { text(en: "Folder", pt: "Pasta") }
    var addAccount: String { text(en: "Add account...", pt: "Adicionar conta…") }
    var accountAlias: String { text(en: "Alias", pt: "Apelido") }
    var removeAccountHelp: String {
        text(en: "Remove from the list. This does not delete anything from disk and disables the account schedules.",
             pt: "Remover da lista (não apaga nada do disco; desabilita os agendamentos da conta)")
    }
    var accountsFooter: String {
        text(en: "Choose a config folder for a Claude Code or Codex account. The name is free; the type is inferred from its contents. Schedules are created in Schedules.",
             pt: "Aponte a pasta de config de uma conta (Claude Code ou Codex) — o nome é livre; o tipo é inferido pelo conteúdo. Agendamentos são criados na aba Horários.")
    }
    var invalidFolderTitle: String { text(en: "Invalid folder", pt: "Pasta inválida") }
    var invalidFolderMessage: String {
        text(en: "The selected folder does not look like a Claude Code or Codex config folder.",
             pt: "A pasta escolhida não parece uma pasta de config do Claude Code nem do Codex.")
    }

    func activeScheduleCount(_ count: Int) -> String {
        switch count {
        case 0: return text(en: "no active schedules", pt: "nenhum agendamento ativo")
        case 1: return text(en: "1 active schedule", pt: "1 agendamento ativo")
        default: return text(en: "\(count) active schedules", pt: "\(count) agendamentos ativos")
        }
    }

    var noActiveSchedules: String { text(en: "No active schedules", pt: "Nenhum agendamento ativo") }
    var noSchedulesYet: String { text(en: "No schedules yet", pt: "Nenhum agendamento ainda") }
    var noSchedulesDescription: String {
        text(en: "Schedules run commands continuously for each account's 5h window or at fixed times.",
             pt: "Agendamentos disparam comandos de forma contínua (a cada janela de 5h da conta) ou em horários fixos.")
    }
    var newSchedule: String { text(en: "New schedule", pt: "Novo agendamento") }
    var editSchedule: String { text(en: "Edit schedule", pt: "Editar agendamento") }
    var scheduleListFooter: String {
        text(en: "Continuous renews the account's 5h window 24/7 and skips redundant renewals while it is active; fixed times always run on the selected times and days.",
             pt: "Contínuo renova a janela de 5h da conta 24/7 e pula renovações redundantes enquanto ela está ativa; horários fixos sempre disparam nos horários e dias marcados.")
    }
    // Barra da tela Horários: filtros, ordenação e resumo.
    var filter: String { text(en: "Filter", pt: "Filtrar") }
    var allAccountsOption: String { text(en: "All", pt: "Todas") }
    var allOption: String { text(en: "All", pt: "Todos") }
    var statusLabel: String { "Status" }
    var activeOption: String { text(en: "Active", pt: "Ativos") }
    var inactiveOption: String { text(en: "Disabled", pt: "Desativados") }
    var clearFilters: String { text(en: "Clear filters", pt: "Limpar filtros") }
    var sortMenu: String { text(en: "Sort", pt: "Ordenar") }
    var sortDefault: String { text(en: "Default", pt: "Padrão") }
    var sortByNextFire: String { text(en: "Next run", pt: "Próximo disparo") }
    var sortByName: String { text(en: "Name", pt: "Nome") }
    var noFilterMatches: String {
        text(en: "No schedules match the filters",
             pt: "Nenhum agendamento corresponde aos filtros")
    }
    var runNow: String { text(en: "Run now", pt: "Executar agora") }
    var edit: String { text(en: "Edit", pt: "Editar") }
    var delete: String { text(en: "Delete", pt: "Excluir") }

    /// "5 schedules · 3 active" / "5 agendamentos · 3 ativos".
    func scheduleSummary(total: Int, active: Int) -> String {
        let totalPart = total == 1
            ? text(en: "1 schedule", pt: "1 agendamento")
            : text(en: "\(total) schedules", pt: "\(total) agendamentos")
        let activePart = text(en: "\(active) active", pt: "\(active) ativos")
        return "\(totalPart) · \(activePart)"
    }

    /// "next: Sat 17:14" / "próximo: sáb 17:14" — já recebe a data formatada.
    func summaryNext(_ time: String) -> String {
        text(en: "next: \(time)", pt: "próximo: \(time)")
    }

    /// "2 visible" / "2 visíveis" quando algum filtro está ativo.
    func visibleCount(_ count: Int) -> String {
        count == 1
            ? text(en: "1 visible", pt: "1 visível")
            : text(en: "\(count) visible", pt: "\(count) visíveis")
    }
    var fixedTimes: String { text(en: "Fixed times", pt: "Horários fixos") }
    var continuousWindow: String { text(en: "Continuous (5h window)", pt: "Contínua (janela de 5h)") }
    var continuous: String { text(en: "continuous", pt: "contínua") }
    var continuousBadge: String { text(en: "Continuous", pt: "Contínua") }
    var fixedContinuousDescription: String {
        text(en: "Renews at the end of each account 5h window, 24/7.",
             pt: "Renova ao fim de cada janela de 5h da conta, 24/7.")
    }
    var continuousConflict: String {
        text(en: "This account already has a continuous schedule.",
             pt: "Esta conta já tem um agendamento contínuo.")
    }
    var continuousConflictTitle: String {
        text(en: "Continuous schedule conflict", pt: "Conflito de agendamento contínuo")
    }
    var overlappingWindows: String {
        text(en: "Times fall within the same 5h window", pt: "Horários caem na mesma janela de 5h")
    }
    var repetition: String { text(en: "Repetition", pt: "Repetição") }
    var time: String { text(en: "Time", pt: "Horário") }
    var addTime: String { text(en: "Add time", pt: "Adicionar horário") }
    var generateChain: String { text(en: "Generate every 5h…", pt: "Gerar a cada 5h…") }
    var chainAnchor: String { text(en: "Starting at", pt: "A partir de") }
    var generate: String { text(en: "Generate", pt: "Gerar") }
    var days: String { text(en: "Days", pt: "Dias") }
    var type: String { text(en: "Type", pt: "Tipo") }
    var messageSection: String { text(en: "Message", pt: "Mensagem") }
    var scheduleSection: String { text(en: "Schedule", pt: "Agendamento") }
    var nameOptional: String { text(en: "Name (optional)", pt: "Nome (opcional)") }
    var messageOrCommand: String { text(en: "Message or command", pt: "Mensagem ou comando") }
    var none: String { text(en: "None", pt: "Nenhum") }
    var showResponse: String {
        text(en: "Show response (history + notification)",
             pt: "Mostrar resposta (histórico + notificação)")
    }
    var notifyOnSuccess: String {
        text(en: "Notify on macOS when this task runs",
             pt: "Notificar no macOS quando esta tarefa for executada")
    }
    var runInTerminal: String {
        text(en: "Open in Terminal (interactive)",
             pt: "Abrir no Terminal (interativo)")
    }
    var model: String { text(en: "Model", pt: "Modelo") }
    var account: String { text(en: "Account", pt: "Conta") }
    var globalDefault: String { text(en: "Default (global)", pt: "Padrão (global)") }
    var codexDefault: String { text(en: "Default (~/.codex)", pt: "Padrão (~/.codex)") }
    var accountDefaultModel: String { text(en: "Model (account default)", pt: "Modelo (padrão da conta)") }
    var workingDirectoryDefault: String {
        text(en: "Directory (~ by default)", pt: "Diretório (~ por padrão)")
    }
    var chooseDirectory: String { text(en: "Choose", pt: "Escolher") }
    var clearWorkingDirectory: String {
        text(en: "Clear directory", pt: "Limpar diretório")
    }

    func taskKind(_ kind: Message.Kind) -> String {
        switch kind {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .shell: return text(en: "command", pt: "comando")
        }
    }

    var waitingForWindow: String { text(en: "waiting for window", pt: "aguardando janela") }
    var renewalFallbackName: String { text(en: "renewal", pt: "renovação") }
    func renewsAt(_ time: String) -> String { text(en: "renews \(time)", pt: "renova \(time)") }
    func nextAt(_ time: String) -> String { text(en: "next \(time)", pt: "próxima \(time)") }
    func nextHi(_ time: String) -> String { text(en: "next hi \(time)", pt: "próximo hi \(time)") }
    func lastAt(_ time: String, _ mark: String) -> String { text(en: "last \(time) \(mark)", pt: "último \(time) \(mark)") }
    func nextTask(_ name: String, _ date: String) -> String {
        text(en: "Next task: \(name) · \(date)", pt: "Próxima tarefa: \(name) · \(date)")
    }
    func scheduledAccountsHeader(_ count: Int) -> String {
        switch count {
        case 0: return noActiveSchedules
        case 1: return text(en: "1 account with schedules", pt: "1 conta com agendamentos")
        default: return text(en: "\(count) accounts with schedules", pt: "\(count) contas com agendamentos")
        }
    }

    var noHistory: String { text(en: "No runs recorded yet.", pt: "Sem disparos registrados ainda.") }
    var noHistoryDescription: String {
        text(en: "Runs from your schedules will appear here with account and model details.",
             pt: "Os disparos dos seus agendamentos aparecerão aqui com detalhes da conta e do modelo.")
    }
    var historySuccess: String { text(en: "Success", pt: "Sucesso") }
    var historyFailure: String { text(en: "Failed", pt: "Falhou") }
    var historySkipped: String { text(en: "Skipped", pt: "Pulado") }
    var historyMissed: String { text(en: "Missed", pt: "Perdido") }
    var historyUnknownAccount: String { text(en: "Unknown account", pt: "Conta desconhecida") }
    var historyUnknownProvider: String { text(en: "Unknown provider", pt: "Provedor desconhecido") }
    var historyUnknownCommand: String { text(en: "Command not recorded", pt: "Comando não registrado") }
    var historyAccountDefaultModel: String { text(en: "Account default", pt: "Padrão da conta") }
    var historyResponse: String { text(en: "Response", pt: "Resposta") }
    var historyDetails: String { text(en: "Details", pt: "Detalhes") }
    var historyExecutedSuccessfully: String {
        text(en: "Executed successfully", pt: "Executado com sucesso")
    }
    func historyWindowActive(until: String) -> String {
        text(en: "Active window until \(until)", pt: "Janela ativa até \(until)")
    }
    func historyMissedOccurrence(_ occurrence: String) -> String {
        text(en: "Missed at \(occurrence) while the app was closed",
             pt: "Perdido em \(occurrence) enquanto o app estava fechado")
    }
    func historyFooter(limit: Int) -> String {
        text(en: "Last \(limit) runs, newest first.",
             pt: "Últimos \(limit) disparos, mais recentes primeiro.")
    }
    func skippedUntil(_ time: String, _ until: String) -> String {
        text(en: "\(time) - skipped (window until \(until))",
             pt: "\(time) — pulado (janela até \(until))")
    }
    func failed(_ time: String, _ message: String) -> String {
        text(en: "\(time) - failed: \(message)",
             pt: "\(time) — falhou: \(message)")
    }
    func missedWhileClosed(_ time: String, _ occurrence: String) -> String {
        text(en: "\(time) - missed \(occurrence) (app was closed)",
             pt: "\(time) — perdido \(occurrence) (app estava fechado)")
    }
    var alreadyRunningTitle: String {
        text(en: "HiYashi is already running", pt: "O HiYashi já está aberto")
    }
    var alreadyRunningBody: String {
        text(en: "Another instance owns the schedules. This one will quit to avoid duplicate dispatches.",
             pt: "Outra instância já cuida dos agendamentos. Esta vai encerrar para evitar disparos duplicados.")
    }
    func succeeded(_ time: String, _ message: String) -> String {
        text(en: "\(time) - \(message)", pt: "\(time) — \(message)")
    }
    func origin(_ origin: FireOrigin) -> String? {
        switch origin {
        case .manual: return text(en: "manual", pt: "manual")
        case .renewal: return text(en: "renewal", pt: "renovação")
        case .agenda: return text(en: "schedule", pt: "agenda")
        case .scheduled: return nil
        }
    }

    var notificationFailureTitle: String { text(en: "HiYashi: run failed", pt: "HiYashi: disparo falhou") }
    func notificationResponseTitle(_ messageText: String) -> String { "HiYashi: \(messageText)" }
    func notificationSuccessTitle(_ name: String) -> String { "HiYashi: \(name)" }
    /// Corpo curto "conta · HH:MM · resultado"; sem segmento de conta para shell.
    func notificationSuccessBody(account: String?, time: String) -> String {
        let result = text(en: "ran successfully", pt: "executada com sucesso")
        return [account, time, result].compactMap { $0 }.joined(separator: " · ")
    }

    func daysSummary(_ weekdays: Set<Int>) -> String {
        if weekdays == Set(1...7) { return text(en: "every day", pt: "todos os dias") }
        if weekdays == [2, 3, 4, 5, 6] { return text(en: "Mon to Fri", pt: "seg a sex") }
        if weekdays == [1, 7] { return text(en: "weekend", pt: "fim de semana") }
        let names: [String]
        switch language {
        case .english: names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        case .portuguese: names = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
        }
        return weekdays.sorted().map { names[$0 - 1] }.joined(separator: " · ")
    }

    var dayLetters: [String] {
        switch language {
        case .english: return ["S", "M", "T", "W", "T", "F", "S"]
        case .portuguese: return ["D", "S", "T", "Q", "Q", "S", "S"]
        }
    }

    private func text(en: String, pt: String) -> String {
        language == .portuguese ? pt : en
    }
}
