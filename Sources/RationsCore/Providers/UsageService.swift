import Foundation

/// A sign-in in progress. The browser has been opened to `url`.
struct PendingSignIn {
    enum Mode: Equatable {
        /// The browser redirects to our local callback server (Codex, Antigravity).
        case callback
        /// The provider shows a code the user pastes back (Claude).
        case pastedCode
        /// The user types this code into the provider's page while we poll (Copilot).
        case deviceCode(String)
    }

    let url: URL
    let mode: Mode
    /// Completes the flow. `pastedCode` is only used in `.pastedCode` mode.
    let finish: @Sendable (_ pastedCode: String?) async throws -> OAuthTokens
    let cancel: @Sendable () -> Void
}

protocol UsageService: Sendable {
    var provider: Provider { get }
    func beginSignIn() async throws -> PendingSignIn
    func refresh(_ tokens: OAuthTokens) async throws -> OAuthTokens
    func fetchUsage(_ tokens: OAuthTokens) async throws -> UsageSnapshot
}

extension Provider {
    var service: any UsageService {
        switch self {
        case .claude: ClaudeService()
        case .codex: CodexService()
        case .copilot: CopilotService()
        case .antigravity: AntigravityService()
        }
    }
}
