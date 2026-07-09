import Foundation

/// Lê a identidade (e-mail logado) de uma pasta de config do Claude Code,
/// decodificando só o necessário de `<dir>/.claude.json`. Nunca chama o CLI.
enum AccountIdentity {
    private struct ConfigFile: Decodable {
        struct OAuth: Decodable { let emailAddress: String? }
        let oauthAccount: OAuth?
    }

    /// `oauthAccount.emailAddress` de `<dir>/.claude.json`; nil se ausente/ilegível.
    static func email(forConfigDir dir: URL) -> String? {
        let url = dir.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(ConfigFile.self, from: data) else { return nil }
        return cfg.oauthAccount?.emailAddress
    }
}
