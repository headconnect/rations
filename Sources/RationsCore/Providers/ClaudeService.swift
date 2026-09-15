import Foundation

/// Claude usage via the OAuth flow Claude Code uses. The user authorizes in the
/// browser and pastes back the `code#state` string shown by Anthropic.
struct ClaudeService: UsageService {
    let provider = Provider.claude

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private static let authorizeURL = "https://claude.ai/oauth/authorize"
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private static let betaHeader = ["anthropic-beta": "oauth-2025-04-20"]

    func beginSignIn() async throws -> PendingSignIn {
        let pkce = PKCE()
        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: "user:profile user:inference"),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: pkce.state),
        ]
        return PendingSignIn(url: components.url!, mode: .pastedCode, finish: { pasted in
            let parts = (pasted ?? "").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", maxSplits: 1)
            guard let code = parts.first, !code.isEmpty else { throw ServiceError.missingCode }
            guard parts.count == 2, parts[1] == pkce.state else { throw ServiceError.stateMismatch }
            var tokens = try await exchange([
                "grant_type": "authorization_code",
                "code": String(code),
                "state": pkce.state,
                "client_id": Self.clientID,
                "redirect_uri": Self.redirectURI,
                "code_verifier": pkce.verifier,
            ], previous: nil)
            tokens.account = try? await accountLabel(tokens)
            return tokens
        }, cancel: {})
    }

    func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else { throw ServiceError.unauthorized }
        do {
            return try await exchange([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": Self.clientID,
            ], previous: tokens)
        } catch ServiceError.http(400, _) {
            throw ServiceError.unauthorized
        }
    }

    func fetchUsage(_ tokens: OAuthTokens) async throws -> UsageSnapshot {
        let data = try await HTTP.get(Self.usageURL, headers: Self.headers(tokens))
        let usage = try JSONDecoder.apiRawKeys.decode(ClaudeUsage.self, from: data)
        return UsageSnapshot(windows: usage.windows(), fetchedAt: .now)
    }

    private func exchange(_ body: [String: String], previous: OAuthTokens?) async throws -> OAuthTokens {
        let data = try await HTTP.postJSON(Self.tokenURL, body: body)
        let response = try JSONDecoder.api.decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? previous?.refreshToken,
            expiresAt: response.expiresIn.map { Date(timeIntervalSinceNow: $0) },
            account: previous?.account
        )
    }

    private func accountLabel(_ tokens: OAuthTokens) async throws -> String {
        let data = try await HTTP.get(Self.profileURL, headers: Self.headers(tokens))
        let profile = try JSONDecoder.api.decode(Profile.self, from: data)
        let plan = profile.account.hasClaudeMax == true ? "Max" : profile.account.hasClaudePro == true ? "Pro" : nil
        return [profile.account.email, plan.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
    }

    private static func headers(_ tokens: OAuthTokens) -> [String: String] {
        betaHeader.merging(["Authorization": "Bearer \(tokens.accessToken)"]) { $1 }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?
}

private struct Profile: Decodable {
    struct Account: Decodable {
        let email: String?
        let hasClaudeMax: Bool?
        let hasClaudePro: Bool?
    }
    let account: Account
}

/// Decode with `apiRawKeys`: legacy limit keys plus the newer named `limits`
/// array. Unknown legacy keys are shown only when they carry a reset time.
struct ClaudeUsage: Decodable {
    /// Newer responses put model allowances in `limits`, with a display name
    /// instead of a stable top-level key. Percent is relative to that allowance.
    struct ScopedLimit: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable {
                let displayName: String?
                enum CodingKeys: String, CodingKey { case displayName = "display_name" }
            }
            let model: Model?
        }
        let kind: String?
        let percent: Double?
        let resetsAt: Date?
        let scope: Scope?
        let isActive: Bool?
        enum CodingKeys: String, CodingKey {
            case kind, percent, scope
            case resetsAt = "resets_at"
            case isActive = "is_active"
        }
    }

    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct ExtraUsage: Decodable {
        let isEnabled: Bool
        let utilization: Double?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case utilization
        }
    }

    private(set) var limits: [String: Window] = [:]
    private(set) var extraUsage: ExtraUsage?
    private(set) var scopedLimits: [ScopedLimit] = []

    private static let labels: [String: String] = [
        "five_hour": "Session (5h)",
        "seven_day": "Weekly · all models",
        "seven_day_opus": "Weekly · Opus",
        "seven_day_sonnet": "Weekly · Sonnet",
        "seven_day_overage_included": "Weekly · Fable",
        "seven_day_oauth_apps": "Weekly · OAuth apps",
        "seven_day_cowork": "Weekly · Cowork",
    ]
    private static let order = ["five_hour", "seven_day"]

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for key in container.allKeys {
            if key.stringValue == "limits" {
                if var entries = try? container.nestedUnkeyedContainer(forKey: key) {
                    while !entries.isAtEnd {
                        let entry = try entries.superDecoder()
                        if let limit = try? ScopedLimit(from: entry) { scopedLimits.append(limit) }
                    }
                }
            } else if key.stringValue == "extra_usage" {
                extraUsage = try? container.decode(ExtraUsage.self, forKey: key)
            } else if let window = try? container.decodeIfPresent(Window.self, forKey: key), window.utilization != nil {
                limits[key.stringValue] = window
            }
        }
    }

    func windows() -> [UsageWindow] {
        var result = limits
            .filter { Self.labels[$0.key] != nil || $0.value.resetsAt != nil }
            .sorted { rank($0.key) < rank($1.key) }
            .map { key, window in
                UsageWindow(id: key, label: Self.labels[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized,
                            percentUsed: window.utilization ?? 0, resetsAt: window.resetsAt,
                            menuBarRole: key == "five_hour" ? .session : key == "seven_day" ? .weekly : nil)
            }
        let fableLimits = scopedLimits.filter {
            $0.kind == "weekly_scoped" && $0.percent != nil
                && $0.scope?.model?.displayName?.caseInsensitiveCompare("Fable") == .orderedSame
        }
        // Claude displays valid allowances even when is_active is false.
        // Prefer an active record if supplied, but do not hide the fallback.
        if let fable = fableLimits.first(where: { $0.isActive != false }) ?? fableLimits.first,
           let percent = fable.percent {
            // Prefer the named limit when both API representations are present.
            result.removeAll { $0.id == "seven_day_overage_included" }
            result.append(UsageWindow(id: "seven_day_overage_included", label: "Weekly · Fable",
                                      percentUsed: percent, resetsAt: fable.resetsAt))
        }
        if let extra = extraUsage, extra.isEnabled {
            result.append(UsageWindow(id: "extra_usage", label: "Extra usage", percentUsed: extra.utilization ?? 0, resetsAt: nil))
        }
        return result
    }

    private func rank(_ key: String) -> (Int, String) {
        (Self.order.firstIndex(of: key) ?? Self.order.count, key)
    }
}
