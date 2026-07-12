import Foundation

protocol SessionDetecting {
    /// `account` é a pasta da conta (`~/.claude`, `~/.codex`…); o detector
    /// deriva a subpasta de transcripts pelo provider.
    func activeWindowEnd(account: URL) async -> Date?
}

/// Reconstrói a janela de 5h do plano Claude lendo passivamente os transcripts
/// JSONL do Claude Code (estilo similar ao `ccusage blocks`, mas sem arredondamento
/// para hora cheia — a janela começa no horário exato da primeira mensagem).
/// Nunca executa o CLI.
struct SessionDetector: SessionDetecting {
    var clock: Clock = SystemClock()

    /// 24h cobre cadeias de blocos consecutivos (o início do bloco corrente
    /// depende do fim do bloco anterior em uso contínuo).
    static let scanInterval: TimeInterval = 24 * 3600
    static let blockDuration: TimeInterval = 5 * 3600

    func activeWindowEnd(account: URL) async -> Date? {
        let provider = Provider.detect(at: account) ?? .claude
        let transcriptsDir = account.appendingPathComponent(provider.transcriptsSubpath)
        var lookback: TimeInterval = Self.scanInterval
        let maxLookback: TimeInterval = 7 * 24 * 3600
        while true {
            let since = clock.now.addingTimeInterval(-lookback)
            let timestamps = await collectTimestamps(projectsDir: transcriptsDir, since: since).sorted()
            // Se o primeiro timestamp visível está a menos de 5h do início da
            // janela de varredura, a cadeia pode ter sido truncada no meio de
            // um bloco — amplia a varredura até garantir um gap de 5h à esquerda.
            if let first = timestamps.first,
               first.timeIntervalSince(since) < Self.blockDuration,
               lookback < maxLookback {
                lookback = min(lookback * 2, maxLookback)
                continue
            }
            return Self.activeBlockEnd(timestamps: timestamps, now: clock.now)
        }
    }

    // MARK: - Núcleo puro (testável)

    /// Blocos de 5h: início = timestamp exato da primeira mensagem (regra real
    /// da API — o /usage reseta exatamente 5h depois; não há arredondamento
    /// para hora cheia); mensagem após o fim do bloco corrente abre bloco novo.
    static func activeBlockEnd(timestamps: [Date], now: Date) -> Date? {
        var blockEnd: Date?
        for t in timestamps.sorted() {
            guard t <= now else { break }
            if blockEnd == nil || t >= blockEnd! {
                blockEnd = t.addingTimeInterval(blockDuration)
            }
        }
        guard let end = blockEnd, now < end else { return nil }
        return end
    }

    /// Extrai o timestamp por busca de substring — sem decodificar o JSON inteiro.
    static func timestamp(fromLine line: String) -> Date? {
        guard let keyRange = line.range(of: "\"timestamp\":\"") else { return nil }
        let rest = line[keyRange.upperBound...]
        guard let quote = rest.firstIndex(of: "\"") else { return nil }
        let raw = String(rest[..<quote])
        return isoFractional.date(from: raw) ?? iso.date(from: raw)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    // MARK: - Varredura

    private func candidateFiles(projectsDir: URL, since: Date) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let mtime = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  mtime >= since else { continue }
            files.append(url)
        }
        return files
    }

    private func collectTimestamps(projectsDir: URL, since: Date) async -> [Date] {
        var result: [Date] = []
        for url in candidateFiles(projectsDir: projectsDir, since: since) {
            // Leitura mapeada + split síncrono, em vez de `url.lines` async: o
            // stream assíncrono tinha overhead por linha e por chamada; o
            // mapeamento (`.mappedIfSafe`) evita carregar arquivos grandes de
            // uma vez. Um arquivo ilegível (ou um diretório com extensão
            // .jsonl) faz `Data(contentsOf:)` lançar → ignora, nunca bloqueia
            // um disparo legítimo.
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let t = Self.timestamp(fromLine: String(line)), t >= since {
                    result.append(t)
                }
            }
        }
        return result
    }
}
