import Foundation

/// Codex usage via the ChatGPT OAuth flow the Codex CLI uses. The browser
/// redirects to a local callback server, so no manual step is needed.
struct CodexService: UsageService {
    let provider = Provider.codex

    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let authorizeURL = "https://auth.openai.com/oauth/authorize"
    private static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let callbackPorts: [UInt16] = [1455, 1457]
    private static let callbackPath = "/auth/callback"

    func beginSignIn() async throws -> PendingSignIn {
        let pkce = PKCE()
        let server = try await CallbackServer.start(ports: Self.callbackPorts, path: Self.callbackPath)
        let redirectURI = "http://localhost:\(server.port)\(Self.callbackPath)"
        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: "openid profile email offline_access"),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "id_token_add_organizations", value: "true"),
            .init(name: "codex_cli_simplified_flow", value: "true"),
            .init(name: "originator", value: "codex_cli_rs"),
            .init(name: "state", value: pkce.state),
        ]
        return PendingSignIn(url: components.url!, mode: .callback, finish: { _ in
            defer { server.stop() }
            let query = try await server.waitForCallback()
            guard query["state"] == pkce.state else { throw ServiceError.stateMismatch }
            guard let code = query["code"] else { throw ServiceError.missingCode }
            let data = try await HTTP.postForm(Self.tokenURL, body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "client_id": Self.clientID,
                "code_verifier": pkce.verifier,
            ])
            return try Self.tokens(from: data, previous: nil)
        }, cancel: { server.stop() })
    }

    func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else { throw ServiceError.unauthorized }
        let data: Data
        do {
            data = try await HTTP.postJSON(Self.tokenURL, body: [
                "client_id": Self.clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ])
        } catch ServiceError.http(400, _) {
            throw ServiceError.unauthorized
        }
        return try Self.tokens(from: data, previous: tokens)
    }

    func fetchUsage(_ tokens: OAuthTokens) async throws -> UsageSnapshot {
        var headers = ["Authorization": "Bearer \(tokens.accessToken)"]
        headers["ChatGPT-Account-Id"] = tokens.accountID
        let data = try await HTTP.get(Self.usageURL, headers: headers)
        let usage = try JSONDecoder.api.decode(CodexUsage.self, from: data)
        return UsageSnapshot(windows: usage.windows(), fetchedAt: .now, raw: data)
    }

    private static func tokens(from data: Data, previous: OAuthTokens?) throws -> OAuthTokens {
        let response = try JSONDecoder.api.decode(TokenResponse.self, from: data)
        guard let accessToken = response.accessToken ?? previous?.accessToken else { throw ServiceError.malformedResponse }
        let auth = response.idToken.flatMap(JWT.claims)?["https://api.openai.com/auth"] as? [String: Any]
        let email = response.idToken.flatMap(JWT.claims)?["email"] as? String
        let plan = (auth?["chatgpt_plan_type"] as? String).map { "(\($0.capitalized))" }
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: response.refreshToken ?? previous?.refreshToken,
            expiresAt: JWT.expiry(accessToken),
            account: email.map { [$0, plan].compactMap { $0 }.joined(separator: " ") } ?? previous?.account,
            accountID: auth?["chatgpt_account_id"] as? String ?? previous?.accountID
        )
    }
}

private struct TokenResponse: Decodable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?
}

struct CodexUsage: Decodable {
    struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Double?
        let resetAt: Double?
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?
    }

    let rateLimit: RateLimit?

    func windows() -> [UsageWindow] {
        [("primary", rateLimit?.primaryWindow), ("secondary", rateLimit?.secondaryWindow)]
            .compactMap { id, window in
                window.map {
                    UsageWindow(id: id, label: Self.label(seconds: $0.limitWindowSeconds), percentUsed: $0.usedPercent,
                                resetsAt: $0.resetAt.map { Date(timeIntervalSince1970: $0) },
                                menuBarRole: id == "primary" ? .session : .weekly)
                }
            }
    }

    private static func label(seconds: Double?) -> String {
        switch seconds {
        case 18_000: "Session (5h)"
        case 604_800: "Weekly"
        case let s?: s >= 86_400 ? "\(Int(s / 86_400))-day" : "\(Int(s / 3_600))-hour"
        case nil: "Limit"
        }
    }
}
