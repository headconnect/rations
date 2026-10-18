import Foundation

/// What the hub serves for one signed-in account: the identity CLIProxyAPI's
/// `auth-files` lists, and the provider's last usage response. Never tokens.
struct HubAccount: Equatable, Sendable {
    let id: UUID
    let provider: Provider
    let email: String?
    /// Codex only: the ChatGPT workspace the quota belongs to.
    let chatGPTAccountID: String?
    /// nil until the first successful fetch.
    let usage: Data?

    /// The services label accounts "email (Plan)"; the hub only wants the address.
    static func email(fromLabel label: String?) -> String? {
        guard let label else { return nil }
        let address = label.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return address.contains("@") ? address : nil
    }
}

/// The two CLIProxyAPI management endpoints T3 Code reads quota through.
///
/// A real hub's `api-call` sends any request with the pooled account's token.
/// This one only answers the GET of each provider's usage URL, from the
/// response Rations already fetched on its own schedule: no upstream request,
/// no token, and anything else (Codex reset credits included) is refused.
enum HubAPI {
    struct Request: Equatable, Sendable {
        let method: String
        /// Without the query string.
        let path: String
        /// Names lowercased.
        let headers: [String: String]
        let body: Data
    }

    struct Response: Equatable, Sendable {
        let status: Int
        let body: Data
    }

    static let usageURLs: [Provider: String] = [
        .claude: "https://api.anthropic.com/api/oauth/usage",
        .codex: "https://chatgpt.com/backend-api/wham/usage",
    ]

    static func respond(to request: Request, key: String, accounts: [HubAccount]) -> Response {
        guard authorized(request, key: key) else { return error(401, "invalid management key") }
        switch request.path {
        case "/v0/management/auth-files":
            guard request.method == "GET" else { return error(405, "method not allowed") }
            return json(200, AuthFiles(files: accounts.filter { usageURLs[$0.provider] != nil }.map(AuthFile.init)))
        case "/v0/management/api-call":
            guard request.method == "POST" else { return error(405, "method not allowed") }
            return apiCall(request.body, accounts: accounts)
        default:
            return error(404, "not found")
        }
    }

    private static func apiCall(_ body: Data, accounts: [HubAccount]) -> Response {
        guard let call = try? JSONDecoder().decode(APICall.self, from: body) else {
            return error(400, "invalid request body")
        }
        guard let account = accounts.first(where: { $0.id.uuidString == call.authIndex }),
              let usageURL = usageURLs[account.provider] else {
            return error(404, "auth file not found")
        }
        guard (call.method ?? "GET").uppercased() == "GET", call.url == usageURL else {
            return json(200, APIResult(statusCode: 403, body: "Rations only serves usage."))
        }
        guard let usage = account.usage else {
            return json(200, APIResult(statusCode: 503, body: "Rations has not fetched usage for this account yet."))
        }
        return json(200, APIResult(statusCode: 200, body: String(decoding: usage, as: UTF8.self)))
    }

    /// CLIProxyAPI takes the key as a bearer token or in `X-Management-Key`.
    /// An empty key never matches, so a hub without one serves nothing.
    private static func authorized(_ request: Request, key: String) -> Bool {
        let bearer = request.headers["authorization"].flatMap { value -> String? in
            value.lowercased().hasPrefix("bearer ") ? String(value.dropFirst(7)) : nil
        }
        guard !key.isEmpty, let given = bearer ?? request.headers["x-management-key"] else { return false }
        return constantTimeEqual(Array(given.utf8), Array(key.utf8))
    }

    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func json(_ status: Int, _ value: some Encodable) -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return Response(status: status, body: (try? encoder.encode(value)) ?? Data())
    }

    private static func error(_ status: Int, _ message: String) -> Response {
        json(status, ["error": message])
    }

    // MARK: Wire format

    private struct AuthFiles: Encodable {
        let files: [AuthFile]
    }

    private struct AuthFile: Encodable {
        struct IDToken: Encodable {
            let chatgptAccountID: String
            enum CodingKeys: String, CodingKey { case chatgptAccountID = "chatgpt_account_id" }
        }

        let id: String
        let authIndex: String
        let provider: String
        let email: String?
        let disabled = false
        let idToken: IDToken?

        init(_ account: HubAccount) {
            id = account.id.uuidString
            authIndex = account.id.uuidString
            provider = account.provider.rawValue
            email = account.email
            idToken = account.chatGPTAccountID.map(IDToken.init)
        }

        enum CodingKeys: String, CodingKey {
            case id, provider, email, disabled
            case authIndex = "auth_index"
            case idToken = "id_token"
        }
    }

    private struct APICall: Decodable {
        let authIndex: String
        let method: String?
        let url: String
        enum CodingKeys: String, CodingKey {
            case method, url
            case authIndex = "auth_index"
        }
    }

    private struct APIResult: Encodable {
        let statusCode: Int
        let body: String
        enum CodingKeys: String, CodingKey {
            case body
            case statusCode = "status_code"
        }
    }
}
