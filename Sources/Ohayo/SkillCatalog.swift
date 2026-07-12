import Foundation

/// Referência a uma skill instalada na conta — o nome é o identificador de
/// invocação no CLI (ex.: "gmud", "superpowers:brainstorming").
struct SkillRef: Equatable, Hashable, Identifiable {
    let name: String
    var id: String { name }
}

/// Varredura pura das skills instaladas em uma conta. Sem cache nem estado:
/// o form consulta ao abrir / trocar conta / trocar tipo — é enumeração local
/// de diretórios pequenos.
enum SkillCatalog {
    /// Skills da conta, ordenadas alfabeticamente e deduplicadas.
    /// Claude: `<dir>/skills/` (pessoais) + `<dir>/plugins/cache/` (plugins,
    /// nome `plugin:skill`). Codex: só `<dir>/skills/` (`.system` é oculta).
    static func skills(for provider: Provider, at configDir: URL) -> [SkillRef] {
        var names = Set(personalSkills(in: configDir.appendingPathComponent("skills")))
        if provider == .claude {
            names.formUnion(pluginSkills(in: configDir.appendingPathComponent("plugins/cache")))
        }
        return names.sorted().map(SkillRef.init)
    }

    /// Pastas `<dir>/<nome>/SKILL.md`; ocultas (ex.: `.system`) ficam de fora.
    private static func personalSkills(in dir: URL) -> [String] {
        subdirectories(of: dir).filter(hasSkillFile).map(\.lastPathComponent)
    }

    /// `<cache>/<marketplace>/<plugin>/<versão>/skills/<nome>/SKILL.md` →
    /// `plugin:nome`. Versões múltiplas do mesmo plugin deduplicam no Set do
    /// chamador.
    private static func pluginSkills(in cacheDir: URL) -> [String] {
        subdirectories(of: cacheDir).flatMap { marketplace in
            subdirectories(of: marketplace).flatMap { plugin in
                subdirectories(of: plugin).flatMap { version in
                    subdirectories(of: version.appendingPathComponent("skills"))
                        .filter(hasSkillFile)
                        .map { "\(plugin.lastPathComponent):\($0.lastPathComponent)" }
                }
            }
        }
    }

    private static func subdirectories(of dir: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func hasSkillFile(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("SKILL.md").path)
    }
}
