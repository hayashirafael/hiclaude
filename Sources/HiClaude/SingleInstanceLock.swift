import Foundation

/// Garante uma única instância do app via `flock` num arquivo de lock.
/// Funciona igual para o binário de dev (`swift run`, sem bundle) e para o
/// .app empacotado, e o kernel libera o lock sozinho quando o processo morre
/// (mesmo com kill -9) — sem risco de lock órfão.
final class SingleInstanceLock {
    private var fd: Int32 = -1

    static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/HiClaude/instance.lock").path
    }

    /// `true` quando este processo obteve o lock; `false` quando outra
    /// instância viva já o segura. Falha inesperada de I/O não bloqueia o app
    /// (melhor duas instâncias do que nenhuma).
    func acquire(path: String = SingleInstanceLock.defaultPath) -> Bool {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let handle = open(path, O_CREAT | O_RDWR, 0o644)
        guard handle >= 0 else { return true }
        guard flock(handle, LOCK_EX | LOCK_NB) == 0 else {
            close(handle)
            return false
        }
        fd = handle // mantém o descritor aberto pela vida do processo
        return true
    }

    func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    deinit { release() }
}
