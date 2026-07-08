import Foundation

protocol SessionDetecting {
    func activeWindowEnd() async -> Date?
}

/// Reconstrói a janela de 5h do plano Claude lendo passivamente os transcripts
/// JSONL do Claude Code (mesma técnica do `ccusage blocks`). Nunca executa o CLI.
struct SessionDetector: SessionDetecting {
    var projectsDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    var clock: Clock = SystemClock()

    /// 24h cobre cadeias de blocos consecutivos (o início do bloco corrente
    /// depende do fim do bloco anterior em uso contínuo).
    static let scanInterval: TimeInterval = 24 * 3600
    static let blockDuration: TimeInterval = 5 * 3600

    func activeWindowEnd() async -> Date? {
        var lookback: TimeInterval = Self.scanInterval
        let maxLookback: TimeInterval = 7 * 24 * 3600
        while true {
            let since = clock.now.addingTimeInterval(-lookback)
            let timestamps = await collectTimestamps(since: since).sorted()
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

    /// Blocos de 5h: início = primeira mensagem arredondada para a hora cheia;
    /// mensagem após o fim do bloco corrente abre bloco novo.
    static func activeBlockEnd(timestamps: [Date], now: Date) -> Date? {
        var blockEnd: Date?
        for t in timestamps.sorted() {
            guard t <= now else { break }
            if blockEnd == nil || t >= blockEnd! {
                blockEnd = floorToHour(t).addingTimeInterval(blockDuration)
            }
        }
        guard let end = blockEnd, now < end else { return nil }
        return end
    }

    static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
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

    private func candidateFiles(since: Date) -> [URL] {
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

    private func collectTimestamps(since: Date) async -> [Date] {
        var result: [Date] = []
        for url in candidateFiles(since: since) {
            do {
                // Streaming linha a linha — nunca carrega o arquivo inteiro
                for try await line in url.lines {
                    if let t = Self.timestamp(fromLine: line), t >= since {
                        result.append(t)
                    }
                }
            } catch {
                continue // arquivo ilegível → ignora (nunca bloquear um disparo legítimo)
            }
        }
        return result
    }
}
