import Foundation

/// Antigravity's Google OAuth client. The id is public. Google's token
/// endpoint also wants the client secret, which Rations does not ship: it is
/// read from the user's own Antigravity install (the `agy` CLI or
/// Antigravity.app) the first time it is needed, checked against Google, and
/// kept in memory until the app quits.
enum AntigravityClient {
    static let id = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    /// Google client secrets: this prefix and 28 more characters. Go binaries
    /// store strings back to back, so the length is what ends one.
    private static let prefix = Data("GOCSPX-".utf8)
    private static let bodyLength = 28
    private static let cache = Cache()

    /// The secret that goes with `id`. Throws `antigravityClient` when no
    /// install is found or none of its secrets is accepted, and rethrows
    /// network errors so being offline is not reported as a missing install.
    static func secret() async throws -> String {
        try await cache.value {
            let found = await cache.candidates {
                installFiles().flatMap { url in
                    (try? Data(contentsOf: url, options: .alwaysMapped)).map(secrets) ?? []
                }
            }
            guard !found.isEmpty else {
                throw ServiceError.antigravityClient("Install Antigravity or its agy CLI, then try again.")
            }
            // An install carries secrets for several Google clients.
            for candidate in Array(NSOrderedSet(array: found)) as! [String] where try await accepts(candidate) {
                return candidate
            }
            // Perhaps an update since the scan; look again next time.
            await cache.forgetScan()
            throw ServiceError.antigravityClient("The installed Antigravity has none Rations recognises; it may have changed.")
        }
    }

    /// Every client secret in a file's bytes, in order of appearance.
    static func secrets(in data: Data) -> [String] {
        var found: [String] = []
        var start = data.startIndex
        while let match = data.range(of: prefix, in: start..<data.endIndex) {
            let end = match.upperBound + bodyLength
            guard end <= data.endIndex else { break }
            let body = data[match.upperBound..<end]
            if body.allSatisfy(isSecretByte) {
                found.append(String(decoding: data[match.lowerBound..<end], as: UTF8.self))
            }
            start = match.upperBound
        }
        return found
    }

    private static func isSecretByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"): true
        default: false
        }
    }

    /// The `agy` CLI where its installer and Homebrew put it, and the
    /// language server binaries inside Antigravity.app.
    private static func installFiles() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cli = [home.appending(path: ".local/bin/agy"), URL(filePath: "/opt/homebrew/bin/agy"),
                   URL(filePath: "/usr/local/bin/agy")]
        let apps = [URL(filePath: "/Applications/Antigravity.app"), home.appending(path: "Applications/Antigravity.app")]
        let bundled = apps.flatMap { app -> [URL] in
            guard let files = FileManager.default.enumerator(
                at: app.appending(path: "Contents"), includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [] }
            return files.compactMap { $0 as? URL }.filter {
                $0.lastPathComponent.hasPrefix("language_server") || $0.lastPathComponent == "agy"
            }
        }
        return (cli + bundled).filter { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// Google answers a made-up refresh token with `invalid_grant` when the
    /// client is right and `invalid_client` (a 401) when the secret is not.
    private static func accepts(_ secret: String) async throws -> Bool {
        do {
            _ = try await HTTP.postForm(tokenURL, body: [
                "grant_type": "refresh_token",
                "refresh_token": "rations-client-check",
                "client_id": id,
                "client_secret": secret,
            ])
            return false
        } catch ServiceError.http(400, let body) {
            return body.contains("invalid_grant")
        } catch ServiceError.unauthorized {
            return false
        }
        // Rate limits, 5xx and network errors say nothing about the secret.
    }

    /// One lookup at a time; a failure is not kept, so installing Antigravity
    /// and trying again works without restarting Rations. What the scan found
    /// is kept, so retrying after a network error does not read the binaries
    /// again; an empty scan is not, for the same reason as above.
    private actor Cache {
        private var task: Task<String, Error>?
        private var scanned: [String]?

        func candidates(_ scan: @Sendable () -> [String]) -> [String] {
            if let scanned { return scanned }
            let found = scan()
            if !found.isEmpty { scanned = found }
            return found
        }

        func forgetScan() { scanned = nil }

        func value(_ load: @escaping @Sendable () async throws -> String) async throws -> String {
            if let task { return try await task.value }
            let task = Task { try await load() }
            self.task = task
            do { return try await task.value } catch {
                self.task = nil
                throw error
            }
        }
    }
}
