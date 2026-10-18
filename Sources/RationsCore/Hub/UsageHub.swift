import Foundation
import Observation
import Security

/// Opt-in: serves the signed-in Claude and Codex accounts' usage to T3 Code as
/// a CLIProxyAPI hub on 127.0.0.1. Follows the `Settings.hubEnabled` and
/// `Settings.hubPort` defaults; the management key lives in the keychain.
@MainActor
@Observable
final class UsageHub {
    enum Status: Equatable {
        case off
        case listening(UInt16)
        case failed(String)
    }

    private(set) var status = Status.off
    /// Empty until the hub is first enabled; the keychain is not read before.
    private(set) var key = ""
    /// Why the last key change was not saved; the old key stays in use.
    private(set) var keyError: String?

    private let store: AccountStore
    private var server: HubServer?
    /// The port the running or starting server was asked for.
    private var serverPort: Int?
    private var startTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init(store: AccountStore) {
        self.store = store
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        sync()
    }

    /// Only an absent value means the default; a typed 0 must still fail the
    /// range check rather than quietly become 8318.
    nonisolated static func port(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: Settings.hubPort) as? Int ?? Settings.defaultHubPort
    }

    var url: String { "http://127.0.0.1:\(Self.port())" }

    /// Accepts any non-blank key; T3 Code sends it back as typed.
    func setKey(_ newKey: String) {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != key else { return }
        do {
            try TokenStore.saveHubKey(trimmed)
            key = trimmed
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
    }

    func regenerateKey() {
        guard let fresh = Self.randomKey() else {
            keyError = Self.randomKeyError
            return
        }
        setKey(fresh)
    }

    private func sync() {
        let wanted = UserDefaults.standard.bool(forKey: Settings.hubEnabled) ? Self.port() : nil
        guard wanted != serverPort else { return }
        stopServer()
        guard let wanted else { return }
        // Set even on failure, so other defaults changes do not retry (and
        // prompt for the keychain) until the user changes the hub settings.
        serverPort = wanted
        guard loadKey() else { return }
        guard let port = UInt16(exactly: wanted), port >= 1024 else {
            status = .failed("Port must be between 1024 and 65535.")
            return
        }
        startTask = Task { await start(port: port) }
    }

    private func start(port: UInt16) async {
        do {
            let server = try HubServer(port: port) { [weak self] request in
                await self?.respond(to: request) ?? HubAPI.Response(status: 503, body: Data())
            }
            self.server = server
            try await server.start()
            guard !Task.isCancelled else { return server.stop() }
            status = .listening(port)
        } catch {
            guard !Task.isCancelled else { return }
            server = nil
            status = .failed("Could not listen on port \(port): \(error.localizedDescription)")
        }
    }

    private func stopServer() {
        startTask?.cancel()
        startTask = nil
        server?.stop()
        server = nil
        serverPort = nil
        status = .off
    }

    private func respond(to request: HubAPI.Request) -> HubAPI.Response {
        HubAPI.respond(to: request, key: key, accounts: accounts)
    }

    /// Signed-in accounts the hub can serve, with their last response.
    private var accounts: [HubAccount] {
        store.monitors.compactMap { monitor in
            guard let tokens = monitor.tokens, HubAPI.usageURLs[monitor.provider] != nil else { return nil }
            return HubAccount(id: monitor.id, provider: monitor.provider,
                              email: HubAccount.email(fromLabel: tokens.account),
                              chatGPTAccountID: monitor.provider == .codex ? tokens.accountID : nil,
                              usage: monitor.snapshot?.raw)
        }
    }

    /// Reads the stored key, or makes one on first use. False if the keychain failed.
    private func loadKey() -> Bool {
        guard key.isEmpty else { return true }
        do {
            if let stored = try TokenStore.loadHubKey(), !stored.isEmpty {
                key = stored
            } else {
                guard let fresh = Self.randomKey() else {
                    status = .failed(Self.randomKeyError)
                    return false
                }
                try TokenStore.saveHubKey(fresh)
                key = fresh
            }
            return true
        } catch {
            status = .failed(error.localizedDescription)
            return false
        }
    }

    private static let randomKeyError = "Could not generate a random key."

    /// 32 random bytes, base64url without padding. nil if the system random
    /// generator fails, rather than a key derived from the zeroed buffer.
    nonisolated static func randomKey() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
