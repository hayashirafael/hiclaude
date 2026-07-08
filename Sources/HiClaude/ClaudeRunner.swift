import Foundation

enum RunnerError: Error, Equatable {
    case cliNotFound
    case timeout
    case failed(String)

    var userMessage: String {
        switch self {
        case .cliNotFound: return "CLI do Claude não encontrado"
        case .timeout: return "claude -p não respondeu em 60s"
        case .failed(let message): return message
        }
    }
}

protocol ClaudeRunning {
    func sendHi() async -> Result<Void, RunnerError>
}

struct ClaudeRunner: ClaudeRunning {
    var timeout: TimeInterval = 60
    var binaryOverride: URL? // testes

    /// Caminhos comuns de instalação; fallback via shell de login cobre
    /// nvm/asdf e instalações exóticas (importante para open source).
    static let candidatePaths = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
    ]

    static func locateClaude() -> URL? {
        let fm = FileManager.default
        for path in candidatePaths {
            let expanded = NSString(string: path).expandingTildeInPath
            if fm.isExecutableFile(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let path = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    func sendHi() async -> Result<Void, RunnerError> {
        guard let binary = binaryOverride ?? Self.locateClaude() else {
            return .failure(.cliNotFound)
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["-p", "hi"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin"
        env["PATH"] = [env["PATH"], extraPath].compactMap { $0 }.joined(separator: ":")
        process.environment = env

        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if process.isRunning {
            process.terminate()
            return .failure(.timeout)
        }
        if process.terminationStatus != 0 {
            let data = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .failure(.failed(message.isEmpty ? "exit \(process.terminationStatus)" : message))
        }
        return .success(())
    }
}
