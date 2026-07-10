import Foundation

/// Caminhos de suporte do HiYashi e compatibilidade com o nome anterior.
enum AppPaths {
    static func legacySupportDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/HiClaude")
    }

    static func supportDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/HiYashi")
    }

    /// O lock permanece no caminho legado para que versões HiClaude e HiYashi
    /// disputem o mesmo inode e nunca disparem agendamentos simultaneamente.
    static func instanceLockPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        legacySupportDirectory(home: home).appendingPathComponent("instance.lock").path
    }

    /// Migração idempotente: move itens ainda ausentes no diretório novo e
    /// preserva o lock legado. Destinos existentes nunca são sobrescritos.
    static func migrateSupportDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        let legacy = legacySupportDirectory(home: home)
        let current = supportDirectory(home: home)
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        try? fileManager.createDirectory(at: current, withIntermediateDirectories: true)
        guard let children = try? fileManager.contentsOfDirectory(
            at: legacy, includingPropertiesForKeys: nil
        ) else { return }
        for source in children where source.lastPathComponent != "instance.lock" {
            let destination = current.appendingPathComponent(source.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.moveItem(at: source, to: destination)
        }
    }

    static func workspaceDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL {
        let current = supportDirectory(home: home).appendingPathComponent("workspace")
        if fileManager.fileExists(atPath: current.path) { return current }
        let legacy = legacySupportDirectory(home: home).appendingPathComponent("workspace")
        if fileManager.fileExists(atPath: legacy.path) { return legacy }
        return current
    }
}
