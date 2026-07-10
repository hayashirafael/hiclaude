import Foundation

protocol Notifying {
    func notifyFailure(message: String)
    func notifyResponse(messageText: String, response: String)
}

struct NullNotifier: Notifying {
    func notifyFailure(message: String) {}
    func notifyResponse(messageText: String, response: String) {}
}

/// Orquestra um disparo: detector → (pula | executa) → registra em AppState.
@MainActor
final class FireController {
    private let state: AppState
    private let detector: SessionDetecting
    private let runner: CommandRunning
    private let notifier: Notifying
    private let clock: Clock
    private var isRunning = false

    static let responseLimit = 4000

    init(state: AppState, detector: SessionDetecting, runner: CommandRunning,
         notifier: Notifying, clock: Clock = SystemClock()) {
        self.state = state
        self.detector = detector
        self.runner = runner
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
        guard !isRunning else { return false } // disparo em andamento → ignora o novo
        isRunning = true
        defer { isRunning = false }

        let accountDir = state.effectiveConfigDir(for: message)
        let account = accountDir.lastPathComponent

        // O skip por janela ativa vale para os kinds que abrem janela (Claude e
        // Codex). Comando cru sempre roda no horário.
        if message.kind != .shell,
           let end = await detector.activeWindowEnd(account: accountDir) {
            state.recordEvent(FireEvent(date: clock.now, result: .skipped(activeUntil: end),
                                        messageText: message.text, account: account, origin: origin))
            return true
        }

        switch await runner.run(message) {
        case .success(let output):
            state.cliFound[message.kind == .codex ? .codex : .claude] = true
            let response = message.resolvedShowResponse && !output.isEmpty
                ? String(output.prefix(Self.responseLimit)) : nil
            state.recordEvent(FireEvent(date: clock.now, result: .success,
                                        messageText: message.text, account: account,
                                        origin: origin, response: response))
            if let response {
                notifier.notifyResponse(messageText: message.text, response: response)
            }
        case .failure(let error):
            if case .cliNotFound(let provider) = error { state.cliFound[provider] = false }
            let summary: String
            var detail: String? = nil
            if case .failed(let full) = error {
                summary = Self.failureSummary(full)
                if full != summary { detail = String(full.prefix(Self.responseLimit)) }
            } else {
                summary = error.userMessage
            }
            state.recordEvent(FireEvent(date: clock.now, result: .failure(message: summary),
                                        messageText: message.text, account: account,
                                        origin: origin, response: detail))
            if origin != .manual { notifier.notifyFailure(message: summary) }
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
