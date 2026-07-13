import Foundation
import os

protocol Notifying {
    func notifyFailure(title: String, message: String)
    func notifyResponse(title: String, response: String)
    func notifySuccess(title: String, body: String)
}

/// Orquestra um disparo: renovação redundante pode pular; demais origens
/// executam e registram o resultado em AppState.
@MainActor
final class FireController {
    private let state: AppState
    private let detector: SessionDetecting
    private let runner: CommandRunning
    private let terminalLauncher: TerminalLaunching?
    private let authenticationChecker: AuthenticationChecking
    private let notifier: Notifying
    private let clock: Clock
    private var isRunning = false
    private let log = Logger(subsystem: "io.github.hayashirafael.Ohayo", category: "fire")

    static let responseLimit = 4000

    init(state: AppState, detector: SessionDetecting, runner: CommandRunning,
         terminalLauncher: TerminalLaunching? = nil,
         notifier: Notifying, clock: Clock = SystemClock(),
         authenticationChecker: AuthenticationChecking = AllowAllAuthenticationChecker()) {
        self.state = state
        self.detector = detector
        self.runner = runner
        self.terminalLauncher = terminalLauncher
        self.authenticationChecker = authenticationChecker
        self.notifier = notifier
        self.clock = clock
    }

    /// Retorna `true` quando o disparo de fato executou (sucesso, falha ou
    /// pulado por janela ativa) e `false` apenas quando foi descartado pelo
    /// guard `isRunning` (outro disparo, de qualquer origem, em andamento).
    /// A renovação usa esse retorno para não marcar dedupe num disparo que
    /// nunca aconteceu de verdade (ver RenewalEngine.renew).
    @discardableResult
    func fire(message: Message, origin: FireOrigin, taskName: String? = nil) async -> Bool {
        guard !isRunning else {
            // Descarte silencioso: outro disparo está em andamento e o novo é
            // engolido. Logamos como erro para tornar visível esse "silenciador".
            log.error("fire: DESCARTADO por isRunning (outro disparo em andamento) origin=\(String(describing: origin), privacy: .public) msg=\(message.text, privacy: .private)")
            return false // disparo em andamento → ignora o novo
        }
        isRunning = true
        defer { isRunning = false }

        let accountDir = state.effectiveConfigDir(for: message)
        let account = accountDir.lastPathComponent

        // Conta pausada: descarta sem executar nem registrar. Retorna true para
        // os engines não re-tentarem via pendingRetry — ao retomar, vale só o
        // próximo evento da cadeia (nunca catch-up retroativo do que foi pausado).
        // Exceção: disparo manual (.manual) sobrepõe a pausa — é ação explícita
        // do usuário na tela ("Executar agora"), que sempre executa (mesma
        // semântica do shell, que nunca é pausado).
        if origin != .manual, message.kind != .shell, state.isPaused(accountDir) {
            log.info("fire: descartado — conta pausada origin=\(String(describing: origin), privacy: .public) conta=\(account, privacy: .public)")
            return true
        }

        // Passou o guard: este disparo assume a execução (isRunning=true).
        log.info("fire: inicio origin=\(String(describing: origin), privacy: .public) conta=\(account, privacy: .public) msg=\(message.text, privacy: .private)")

        // Só a renovação contínua evita um disparo redundante. Horários fixos
        // são compromissos de execução (inclusive no batch com resposta) e
        // devem rodar mesmo quando a conta já tem uma janela ativa.
        if origin == .renewal, message.kind != .shell,
           let end = await detector.activeWindowEnd(account: accountDir) {
            log.info("fire: renovacao pulada (janela ativa ate \(String(describing: end), privacy: .public)) conta=\(account, privacy: .public)")
            state.recordEvent(state.makeEvent(date: clock.now,
                                              result: .skipped(activeUntil: end),
                                              message: message, origin: origin))
            return true
        }

        if message.kind != .shell {
            switch await authenticationChecker.status(for: message.kind == .codex ? .codex : .claude,
                                                       configDir: accountDir) {
            case .authenticated, .unknown:
                break
            case .unauthenticated(let log):
                let provider: Provider = message.kind == .codex ? .codex : .claude
                let summary = state.strings.authenticationRequired(provider, configDir: accountDir)
                state.recordEvent(state.makeEvent(date: clock.now,
                                                  result: .failure(message: summary),
                                                  message: message, origin: origin,
                                                  response: log.isEmpty ? nil : String(log.prefix(Self.responseLimit))))
                if origin != .manual {
                    notifier.notifyFailure(title: state.strings.notificationFailureTitle,
                                           message: summary)
                }
                return true
            }
        }

        if message.resolvedRunInTerminal, let terminalLauncher {
            switch await terminalLauncher.launch(message) {
            case .success:
                log.info("fire: launch terminal ok conta=\(account, privacy: .public)")
                state.cliFound[message.kind == .codex ? .codex : .claude] = true
                state.recordEvent(state.makeEvent(date: clock.now, result: .success,
                                                  message: message, origin: origin))
                if message.resolvedNotifyOnSuccess {
                    notifySuccess(message: message, taskName: taskName, accountDir: accountDir)
                }
            case .failure(let error):
                if case .cliNotFound(let provider) = error { state.cliFound[provider] = false }
                let summary = error.userMessage(language: state.language)
                log.error("fire: launch terminal falhou: \(summary, privacy: .public)")
                state.recordEvent(state.makeEvent(date: clock.now,
                                                  result: .failure(message: summary),
                                                  message: message, origin: origin))
                if origin != .manual {
                    notifier.notifyFailure(title: state.strings.notificationFailureTitle,
                                           message: summary)
                }
            }
            return true
        }

        switch await runner.run(message) {
        case .success(let output):
            log.info("fire: runner ok conta=\(account, privacy: .public)")
            state.cliFound[message.kind == .codex ? .codex : .claude] = true
            let response = message.resolvedShowResponse && !output.isEmpty
                ? String(output.prefix(Self.responseLimit)) : nil
            state.recordEvent(state.makeEvent(date: clock.now, result: .success,
                                              message: message, origin: origin,
                                              response: response))
            if let response {
                // A notificação de resposta já comunica o sucesso — não duplica.
                notifier.notifyResponse(title: state.strings.notificationResponseTitle(message.text),
                                        response: response)
            } else if message.resolvedNotifyOnSuccess {
                notifySuccess(message: message, taskName: taskName, accountDir: accountDir)
            }
        case .failure(let error):
            if case .cliNotFound(let provider) = error { state.cliFound[provider] = false }
            let summary: String
            var detail: String? = nil
            if case .failed(let full) = error {
                summary = Self.failureSummary(full)
                if full != summary {
                    let truncated = String(full.prefix(Self.responseLimit))
                    detail = full.count > Self.responseLimit
                        ? truncated + "\n[log truncated]" : truncated
                }
            } else {
                summary = error.userMessage(language: state.language)
            }
            log.error("fire: runner falhou: \(summary, privacy: .public)")
            state.recordEvent(state.makeEvent(date: clock.now,
                                              result: .failure(message: summary),
                                              message: message, origin: origin,
                                              response: detail))
            if origin != .manual {
                notifier.notifyFailure(title: state.strings.notificationFailureTitle, message: summary)
            }
        }
        return true
    }

    /// Notificação opt-in de sucesso (notifyOnSuccess): título com o nome da
    /// tarefa (fallback no texto do comando), corpo "conta · HH:MM · resultado".
    /// Sem gate por origem — a flag é opt-in explícito por tarefa; a contínua
    /// notifica a cada renovação efetiva, nunca nos skips (sem hook lá).
    private func notifySuccess(message: Message, taskName: String?, accountDir: URL) {
        let accountLabel = message.kind == .shell ? nil : state.label(for: accountDir)
        notifier.notifySuccess(
            title: state.strings.notificationSuccessTitle(taskName ?? message.text),
            body: state.strings.notificationSuccessBody(
                account: accountLabel,
                time: Fmt.hhmm(clock.now, language: state.language)))
    }

    /// Resumo de um log longo para o título do histórico: a última linha não
    /// vazia (onde CLIs imprimem o erro final), truncada — o texto completo
    /// vai em `response` e vira detalhe expansível na UI.
    static func failureSummary(_ full: String) -> String {
        let line = full.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? full
        return String(line.prefix(120))
    }
}

struct AllowAllAuthenticationChecker: AuthenticationChecking {
    func status(for provider: Provider, configDir: URL) async -> AuthenticationStatus {
        .authenticated
    }
}
