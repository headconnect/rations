import Foundation

enum HTTP {
    static let userAgent = "rations/\(UpdateChecker.currentVersion) (macOS)"

    static func get(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await send(request)
    }

    static func postJSON(_ url: URL, body: some Encodable, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    static func postForm(_ url: URL, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = body.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 30
        // Antigravity sends the client's own; everything else identifies as Rations.
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401: throw ServiceError.unauthorized
        case 429: throw ServiceError.rateLimited
        default: throw ServiceError.http(status, String(decoding: data.prefix(200), as: UTF8.self))
        }
    }
}

extension JSONDecoder {
    /// snake_case keys mapped to camelCase, ISO 8601 dates with or without fractional seconds.
    static let api = make(convertKeys: true)
    /// Same dates, keys left untouched (for payloads with dynamic keys).
    static let apiRawKeys = make(convertKeys: false)

    private static func make(convertKeys: Bool) -> JSONDecoder {
        let decoder = JSONDecoder()
        if convertKeys { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = ISO8601.date(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(text)"))
            }
            return date
        }
        return decoder
    }
}

enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    static func date(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }
}
