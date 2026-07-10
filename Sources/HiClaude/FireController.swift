import Foundation
import os

protocol Notifying {
    func notifyFailure(title: String, message: String)
    func notifyResponse(title: String, response: String)
}

/// Orquestra um disparo: renovação redundante pode pular; demais origens
/// executam e registram o resultado em AppState.
@MainActor
final class FireController {
    private let state: AppState
    private let detector: SessionDetecting
    private let runner: CommandRunning
    private let terminalLauncher: TerminalLaunching?
    private let notifier: Notifying
    private let clock: Clock
    private var isRunning = false
    private let log = Logger(subsystem: "dev.hiclaude", category: "fire")

    static let responseLimit = 4000

    init(state: AppState, detector: SessionDetecting, runner: CommandRunning,
         terminalLauncher: TerminalLaunching? = nil,
         notifier: Notifying, clock: Clock = SystemClock()) {
        self.state = state
        self.detector = detector
        self.runner = runner
        self.terminalLauncher = terminalLauncher
        self.notifier = notifier
        self.clock = clock
    }

    /// Retorna `true` quando o disparo de fato executou (sucesso, falha ou
    /// pulado por janela ativa) e `false` apenas quando foi descartado pelo
    /// guard `isRunning` (outro disparo, de qualquer origem, em andamento).
    /// A renovação usa esse retorno para não marcar dedupe num disparo que
    /// nunca aconteceu de verdade (ver RenewalEngine.renew).
    @discardableResult
    func fire(message: Message, origin: FireOrigin) async -> Bool {
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

        if message.resolvedRunInTerminal, let terminalLauncher {
            switch await terminalLauncher.launch(message) {
            case .success:
                log.info("fire: launch terminal ok conta=\(account, privacy: .public)")
                state.cliFound[message.kind == .codex ? .codex : .claude] = true
                state.recordEvent(state.makeEvent(date: clock.now, result: .success,
                                                  message: message, origin: origin))
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
                notifier.notifyResponse(title: state.strings.notificationResponseTitle(message.text),
                                        response: response)
            }
        case .failure(let error):
            if case .cliNotFound(let provider) = error { state.cliFound[provider] = false }
            let summary: String
            var detail: String? = nil
            if case .failed(let full) = error {
                summary = Self.failureSummary(full)
                if full != summary { detail = String(full.prefix(Self.responseLimit)) }
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

    /// Resumo de um stderr longo para o título do histórico: a última linha
    /// não vazia (onde CLIs imprimem o erro final), truncada — o texto
    /// completo vai em `response` e vira detalhe expansível na UI.
    static func failureSummary(_ full: String) -> String {
        let line = full.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? full
        return String(line.prefix(120))
    }
}
