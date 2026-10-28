import Foundation

/// Google Antigravity usage via the Google OAuth client the Antigravity app and
/// `agy` CLI use (see `AntigravityClient` for its secret). The browser
/// redirects to a local callback server, like Codex.
/// Quotas come from Cloud Code's quota summary, the same data `agy /usage` shows.
struct AntigravityService: UsageService {
    let provider = Provider.antigravity

    private static let authorizeURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
    private static let loadCodeAssistURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    /// The daily endpoint first, as Antigravity does; production if it is missing there.
    private static let quotaURLs = [
        URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!,
        URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!,
    ]
    private static let scopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs",
    ]
    private static let callbackPorts: [UInt16] = [51121, 51122]
    private static let callbackPath = "/oauth-callback"
    private static let headers = ["User-Agent": "antigravity/hub/2.9.1 darwin/arm64"]

    func beginSignIn() async throws -> PendingSignIn {
        // Before the browser opens, so a missing install fails straight away.
        _ = try await AntigravityClient.secret()
        let pkce = PKCE()
        let server = try await CallbackServer.start(ports: Self.callbackPorts, path: Self.callbackPath)
        let redirectURI = "http://localhost:\(server.port)\(Self.callbackPath)"
        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: AntigravityClient.id),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "state", value: pkce.state),
        ]
        return PendingSignIn(url: components.url!, mode: .callback, finish: { _ in
            defer { server.stop() }
            let query = try await server.waitForCallback()
            guard query["state"] == pkce.state else { throw ServiceError.stateMismatch }
            if let error = query["error"] { throw ServiceError.signIn(error) }
            guard let code = query["code"] else { throw ServiceError.missingCode }
            let data = try await HTTP.postForm(AntigravityClient.tokenURL, body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "client_id": AntigravityClient.id,
                "client_secret": try await AntigravityClient.secret(),
                "code_verifier": pkce.verifier,
            ])
            var tokens = try Self.tokens(from: data, previous: nil)
            let assist = try? await loadCodeAssist(tokens)
            tokens.accountID = assist?.cloudaicompanionProject
            tokens.account = try? await accountLabel(tokens, tier: assist?.tierName)
            return tokens
        }, cancel: { server.stop() })
    }

    func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else { throw ServiceError.unauthorized }
        let data: Data
        do {
            data = try await HTTP.postForm(AntigravityClient.tokenURL, body: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": AntigravityClient.id,
                "client_secret": try await AntigravityClient.secret(),
            ])
        } catch ServiceError.http(400, _) {
            throw ServiceError.unauthorized
        }
        var refreshed = try Self.tokens(from: data, previous: tokens)
        if refreshed.accountID == nil {
            refreshed.accountID = try? await loadCodeAssist(refreshed).cloudaicompanionProject
        }
        return refreshed
    }

    func fetchUsage(_ tokens: OAuthTokens) async throws -> UsageSnapshot {
        let project = if let id = tokens.accountID { id } else { try? await loadCodeAssist(tokens).cloudaicompanionProject }
        var body: [String: String] = [:]
        body["project"] = project
        let auth = Self.headers.merging(["Authorization": "Bearer \(tokens.accessToken)"]) { $1 }
        for (index, url) in Self.quotaURLs.enumerated() {
            do {
                let data = try await HTTP.postJSON(url, body: body, headers: auth)
                let usage = try JSONDecoder.api.decode(AntigravityUsage.self, from: data)
                return UsageSnapshot(windows: usage.windows(), fetchedAt: .now)
            } catch ServiceError.http(404, _) where index < Self.quotaURLs.count - 1 {
                continue
            }
        }
        throw ServiceError.malformedResponse
    }

    private func loadCodeAssist(_ tokens: OAuthTokens) async throws -> CodeAssist {
        let body = ["metadata": ["ideType": "ANTIGRAVITY", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]]
        let data = try await HTTP.postJSON(Self.loadCodeAssistURL, body: body,
                                           headers: Self.headers.merging(["Authorization": "Bearer \(tokens.accessToken)"]) { $1 })
        return try JSONDecoder.api.decode(CodeAssist.self, from: data)
    }

    private func accountLabel(_ tokens: OAuthTokens, tier: String?) async throws -> String {
        let data = try await HTTP.get(Self.userInfoURL, headers: ["Authorization": "Bearer \(tokens.accessToken)"])
        let email = try JSONDecoder.api.decode(UserInfo.self, from: data).email
        return [email, tier.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }

    private static func tokens(from data: Data, previous: OAuthTokens?) throws -> OAuthTokens {
        let response = try JSONDecoder.api.decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? previous?.refreshToken,
            expiresAt: response.expiresIn.map { Date(timeIntervalSinceNow: $0) },
            account: previous?.account,
            accountID: previous?.accountID
        )
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?
}

private struct UserInfo: Decodable {
    let email: String?
}

struct CodeAssist: Decodable {
    struct Tier: Decodable {
        let id: String?
        let name: String?
    }

    let cloudaicompanionProject: String?
    let currentTier: Tier?
    let paidTier: Tier?

    /// The paid tier says what the user subscribes to; the current tier is
    /// often a generic "standard" one.
    var tierName: String? { paidTier?.name ?? currentTier?.name }
}

/// Decode with `api`: Cloud Code sends camelCase, the local language server's
/// copy snake_case, and both come out the same.
struct AntigravityUsage: Decodable {
    struct Bucket: Decodable {
        let bucketId: String?
        let displayName: String?
        let window: String?
        let remainingFraction: Double?
        let disabled: Bool?
        let resetTime: Date?
    }

    struct Group: Decodable {
        let displayName: String?
        let buckets: [Bucket]?
    }

    let groups: [Group]?
    /// Buckets outside any group.
    let buckets: [Bucket]?

    /// One window per bucket in API order, e.g. "Gemini · Session (5h)".
    /// Models in a group share both limits, so the menu bar shows the most-used
    /// 5-hour and weekly bucket of the shared groups (those with a 5-hour
    /// limit); a model-only group such as Argon's stays in the popover. Accounts
    /// without any 5-hour limit pick from every weekly bucket. The two headline
    /// windows come first, since `UsageSnapshot.headline` takes them in order.
    func windows() -> [UsageWindow] {
        let entries = (groups ?? []).flatMap { group in (group.buckets ?? []).map { (group, $0) } }
            + (buckets ?? []).map { (nil as Group?, $0) }
        let metered = entries.filter { $0.1.disabled != true && $0.1.remainingFraction != nil && $0.1.bucketId != nil }
        let shared = Set(metered.filter { $0.1.window == "5h" }.compactMap { $0.0?.displayName })
        func mostUsed(_ window: String, among candidates: [(Group?, Bucket)]) -> String? {
            candidates.filter { $0.1.window == window }.min { $0.1.remainingFraction! < $1.1.remainingFraction! }?.1.bucketId
        }
        let weeklyCandidates = shared.isEmpty ? metered : metered.filter { $0.0.map { shared.contains($0.displayName ?? "") } ?? false }
        let session = mostUsed("5h", among: metered)
        let weekly = mostUsed("weekly", among: weeklyCandidates)

        let windows = metered.map { group, bucket in
            let id = bucket.bucketId!
            return UsageWindow(id: id, label: Self.label(group: group?.displayName, bucket: bucket),
                               percentUsed: (1 - bucket.remainingFraction!) * 100, resetsAt: bucket.resetTime,
                               menuBarRole: id == session ? .session : id == weekly ? .weekly : nil,
                               term: bucket.window == "5h" ? .short : .long)
        }
        let order: (UsageWindow) -> Int = { $0.menuBarRole == .session ? 0 : $0.menuBarRole == .weekly ? 1 : 2 }
        return windows.enumerated().sorted { (order($0.element), $0.offset) < (order($1.element), $1.offset) }.map(\.element)
    }

    private static func label(group: String?, bucket: Bucket) -> String {
        let limit = switch bucket.window {
        case "5h": "Session (5h)"
        case "weekly": "Weekly"
        default: bucket.displayName ?? bucket.bucketId ?? "Limit"
        }
        guard var group, !group.isEmpty else { return limit }
        for suffix in [" Models", " models"] where group.hasSuffix(suffix) { group.removeLast(suffix.count) }
        return "\(group) · \(limit)"
    }
}
