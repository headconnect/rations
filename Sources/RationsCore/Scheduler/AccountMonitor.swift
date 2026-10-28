import AppKit
import Foundation
import Observation

/// Owns sign-in state, the latest snapshot and the polling loop for one account.
@MainActor
@Observable
final class AccountMonitor: Identifiable {
    enum Status: Equatable {
        case signedOut
        case signingIn
        case idle
        case refreshing
        case error(String)
    }

    let id: UUID
    /// Kept in sync by the store when the user edits tag, name or menu bar.
    var account: Account
    private(set) var tokens: OAuthTokens?
    private(set) var snapshot: UsageSnapshot?
    private(set) var status: Status = .signedOut
    private(set) var lastChecked: Date?
    private(set) var nextCheck: Date?
    private(set) var policy = RefreshPolicy()
    private(set) var pendingSignIn: PendingSignIn?

    private let service: any UsageService
    /// The store outlives its monitors and owns the keychain vault.
    private unowned let store: AccountStore
    private var loop: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    private var privateSession: PrivateSignInSession?

    var provider: Provider { account.provider }
    var isSignedIn: Bool { tokens != nil }
    var isSigningIn: Bool { pendingSignIn != nil || signInTask != nil }

    init(account: Account, store: AccountStore) {
        id = account.id
        self.account = account
        self.store = store
        service = account.provider.service
        tokens = store.tokens(for: account.id)
        if tokens != nil {
            status = .idle
            startLoop()
        } else if let error = store.vaultError {
            // The tokens may well be there; say why they could not be read
            // rather than silently offering a fresh sign-in.
            status = .error("\(error) Restart the app to try again.")
        }
    }

    // MARK: Polling

    func refreshNow() {
        policy.reset()
        startLoop()
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                await fetchOnce()
                guard !Task.isCancelled else { return }
                let delay = nextDelay()
                nextCheck = Date(timeIntervalSinceNow: delay)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func fetchOnce() async {
        guard var current = tokens else { return }
        status = .refreshing
        do {
            if current.needsRefresh { current = try await refreshTokens(current) }
            let fresh: UsageSnapshot
            do {
                fresh = try await service.fetchUsage(current)
            } catch ServiceError.unauthorized {
                current = try await refreshTokens(current)
                fresh = try await service.fetchUsage(current)
            }
            policy.record(changed: fresh.hasChanges(since: snapshot))
            snapshot = fresh
            lastChecked = .now
            status = .idle
        } catch {
            // A manual refresh cancels the in-flight fetch; the new loop reports instead.
            guard !Task.isCancelled else { return }
            switch error as? ServiceError {
            case .unauthorized: signOut()
            case .rateLimited: policy.backOff()
            default: policy.reset()
            }
            status = .error(error.localizedDescription)
        }
    }

    private func refreshTokens(_ current: OAuthTokens) async throws -> OAuthTokens {
        let fresh = try await service.refresh(current)
        // A sign-out or removal while the reply was in flight must win.
        try Task.checkCancellation()
        try store.setTokens(fresh, for: id)
        tokens = fresh
        return fresh
    }

    /// Policy interval, shortened so a window reset is picked up promptly -
    /// except while rate limited, where the backoff has to win.
    private func nextDelay() -> TimeInterval {
        var delay = policy.interval
        if !policy.isBackingOff, let reset = snapshot?.earliestReset, reset > .now {
            delay = min(delay, reset.timeIntervalSinceNow + 15)
        }
        return max(delay, 30)
    }

    // MARK: Sign-in

    /// `privately` swaps the system browser for a cookie-less window, so a
    /// second account of a provider is not auto-signed-in as the first.
    func signIn(privately: Bool = false) {
        guard !store.isSigningIn else { return }
        runSignInStep { [self] in
            let pending = try await service.beginSignIn()
            // Cancelled while it was starting (a removal, Cancel): close what
            // it opened instead of sending the browser off for a gone account.
            guard !Task.isCancelled else { return pending.cancel() }
            pendingSignIn = pending
            status = .signingIn
            if case .deviceCode(let code) = pending.mode {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
            if privately {
                let session = PrivateSignInSession()
                privateSession = session
                session.start(url: pending.url)
            } else {
                NSWorkspace.shared.open(pending.url)
            }
            if pending.mode != .pastedCode { try await finishSignIn(pending, pastedCode: nil) }
        }
    }

    func submitPastedCode(_ code: String) {
        guard let pending = pendingSignIn, signInTask == nil else { return }
        runSignInStep { [self] in try await finishSignIn(pending, pastedCode: code) }
    }

    func cancelSignIn() {
        stop()
        status = .signedOut
    }

    private func runSignInStep(_ step: @escaping @MainActor () async throws -> Void) {
        signInTask = Task {
            do {
                try await step()
            } catch {
                guard !Task.isCancelled else { return }
                pendingSignIn = nil
                endPrivateSession()
                status = .error(error.localizedDescription)
            }
            if !Task.isCancelled { signInTask = nil }
        }
    }

    private func finishSignIn(_ pending: PendingSignIn, pastedCode: String?) async throws {
        let fresh = try await pending.finish(pastedCode)
        try Task.checkCancellation()
        try store.setTokens(fresh, for: id)
        pendingSignIn = nil
        endPrivateSession()
        tokens = fresh
        snapshot = nil
        refreshNow()
    }

    func signOut() {
        stop()
        try? store.setTokens(nil, for: id)
        tokens = nil
        snapshot = nil
        lastChecked = nil
        nextCheck = nil
        status = .signedOut
    }

    /// Drops all in-flight work; the store handles the tokens.
    func stop() {
        loop?.cancel()
        loop = nil
        signInTask?.cancel()
        signInTask = nil
        pendingSignIn?.cancel()
        pendingSignIn = nil
        endPrivateSession()
    }

    /// The private window never closes itself: no flow redirects to a scheme we
    /// own, so we close it when the sign-in ends, fails or is cancelled.
    private func endPrivateSession() {
        privateSession?.cancel()
        privateSession = nil
    }
}
