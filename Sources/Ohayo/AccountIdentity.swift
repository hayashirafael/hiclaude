import Foundation

/// Lê a identidade (e-mail logado) de uma pasta de conta, sem nunca chamar
/// o CLI. Claude: `.claude.json`. Codex: claim `email` do `id_token` (JWT)
/// em `auth.json` — decodifica só o payload, sem validar assinatura (uso
/// local, apenas exibição).
enum AccountIdentity {
    private struct ConfigFile: Decodable {
        struct OAuth: Decodable { let emailAddress: String? }
        let oauthAccount: OAuth?
    }

    private struct CodexAuthFile: Decodable {
        struct Tokens: Decodable {
            let idToken: String?
            enum CodingKeys: String, CodingKey { case idToken = "id_token" }
        }
        let tokens: Tokens?
    }

    private struct JWTPayload: Decodable { let email: String? }

    /// E-mail logado da conta, roteando pela assinatura do conteúdo da pasta.
    /// Pasta sem assinatura cai no caminho Claude (o `.claude.json` ausente
    /// devolve nil de qualquer forma).
    static func email(forConfigDir dir: URL) -> String? {
        switch Provider.detect(at: dir) ?? .claude {
        case .claude: return claudeEmail(forConfigDir: dir)
        case .codex: return codexEmail(forConfigDir: dir)
        }
    }

    private static func claudeEmail(forConfigDir dir: URL) -> String? {
        let url = dir.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(ConfigFile.self, from: data) else { return nil }
        return cfg.oauthAccount?.emailAddress
    }

    static func codexEmail(forConfigDir dir: URL) -> String? {
        let url = dir.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let auth = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
              let jwt = auth.tokens?.idToken else { return nil }
        return email(fromJWT: jwt)
    }

    /// Claim `email` do payload de um JWT (segmento do meio, base64url).
    static func email(fromJWT jwt: String) -> String? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: data)
        else { return nil }
        return payload.email
    }
}
