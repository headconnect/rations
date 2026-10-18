import Foundation
import Network

/// Minimal HTTP/1.1 server on 127.0.0.1 for the usage hub: one request per
/// connection, answered by `handler`, then closed. Every connection is closed
/// by its deadline at the latest, and all of them when the server stops.
final class HubServer: @unchecked Sendable {
    typealias Handler = @Sendable (HubAPI.Request) async -> HubAPI.Response

    /// Requests carry a small JSON body at most; anything bigger is refused.
    static let maxRequestSize = 64 * 1024
    /// T3 Code polls a handful of accounts at a time; more is someone else.
    static let maxConnections = 16

    private let listener: NWListener
    private let handler: Handler
    private let requestTimeout: TimeInterval
    private let queue = DispatchQueue(label: "no.enso.rations.hub")
    /// Open connections, touched on `queue` only.
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    /// Port 0 picks a free one; read it back from `port`. `requestTimeout`
    /// bounds a connection from accept to response.
    init(port: UInt16, requestTimeout: TimeInterval = 10, handler: @escaping Handler) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw ServiceError.noFreePort }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: endpointPort)
        listener = try NWListener(using: parameters)
        self.requestTimeout = requestTimeout
        self.handler = handler
    }

    var port: UInt16? { listener.port?.rawValue }

    /// Returns once listening; throws if the port cannot be bound.
    func start() async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case .failed(let error), .waiting(let error):
                    // Waiting is how an occupied port shows up; it would retry forever.
                    once.run {
                        listener?.cancel()
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    once.run { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        queue.async { [self] in
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    /// On `queue`, like every listener and connection callback.
    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maxConnections else { return connection.cancel() }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.connections[id] = nil
            default: break
            }
        }
        // A no-op once the response has gone out and closed it.
        queue.asyncAfter(deadline: .now() + requestTimeout) { connection.cancel() }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxRequestSize) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch Self.parse(buffer) {
            case .complete(let request):
                Task {
                    let response = await self.handler(request)
                    self.send(response, on: connection)
                }
            // parse() bounds the headers and the body, each to maxRequestSize.
            case .incomplete where error == nil && !isComplete:
                receive(connection, buffer: buffer)
            case .incomplete, .invalid:
                send(HubAPI.Response(status: 400, body: Data(#"{"error":"bad request"}"#.utf8)), on: connection)
            }
        }
    }

    private func send(_ response: HubAPI.Response, on connection: NWConnection) {
        let head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
            + "Content-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in connection.cancel() })
    }

    enum ParseResult: Equatable {
        case complete(HubAPI.Request)
        case incomplete
        case invalid
    }

    /// Request line, headers, and a body of `Content-Length` bytes. Chunked
    /// bodies are not supported; T3 Code sends its small JSON with a length.
    static func parse(_ data: Data) -> ParseResult {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxRequestSize ? .invalid : .incomplete
        }
        let lines = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"] != nil { return .invalid }
        let length = headers["content-length"].map { Int($0) ?? -1 } ?? 0
        guard (0...maxRequestSize).contains(length) else { return .invalid }
        let body = data[end.upperBound...]
        guard body.count >= length else { return .incomplete }
        let target = String(requestLine[1])
        return .complete(HubAPI.Request(
            method: requestLine[0].uppercased(),
            path: target.components(separatedBy: "?")[0],
            headers: headers,
            body: Data(body.prefix(length))
        ))
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
    }
}

/// Resumes a continuation at most once across listener state callbacks.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
