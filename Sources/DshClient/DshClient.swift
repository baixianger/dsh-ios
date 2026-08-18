import Foundation

/// A peer client for the DeepSeek Harness web API — the same surface the
/// browser UI talks to, usable from any URLSession host (iOS / macOS / CLI).
public struct DshClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let authorizationProvider: (@Sendable () async -> String?)?

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        authorizationProvider: (@Sendable () async -> String?)? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authorizationProvider = authorizationProvider
    }

    private func authorize(_ request: inout URLRequest) async {
        if let value = await authorizationProvider?() {
            request.setValue(value, forHTTPHeaderField: "authorization")
        }
    }

    /// Raw unary RPC: POST /api/{method}, return the result value as JSONValue.
    public func call(_ method: String, payload: JSONValue = .object([:])) async throws -> JSONValue {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent(method)
        var request = URLRequest(url: url)
        await authorize(&request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(ClientRequest(method: method, payload: payload))

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw DshError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        let envelope = try JSONDecoder().decode(ServerResponse.self, from: data)
        guard envelope.result.ok, let value = envelope.result.value else {
            throw envelope.result.error ?? DshError.missingValue
        }
        return value
    }

    /// Typed unary RPC: decode the result value directly into a model.
    public func call<T: Decodable>(_ method: String, payload: JSONValue = .object([:]), as type: T.Type) async throws -> T {
        let value = try await call(method, payload: payload)
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Unary call to a Typert Remote namespace (POST /api/{namespace}/{method})
    /// using the api-gateway's `args` wire shape. Returns the gateway value —
    /// either a nested `{ok, value|error}` business result or the plain result.
    public func callRemote(_ namespace: String, _ method: String, args: JSONValue) async throws -> JSONValue {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent(namespace)
            .appendingPathComponent(method)
        var req = URLRequest(url: url)
        await authorize(&req)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let payload = JSONValue.object(["args": args])
        req.httpBody = try JSONEncoder().encode(ClientRequest(method: "\(namespace)/\(method)", payload: payload))

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw DshError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        let envelope = try JSONDecoder().decode(ServerResponse.self, from: data)
        guard envelope.result.ok, let value = envelope.result.value else {
            throw envelope.result.error ?? DshError.missingValue
        }
        return value
    }

    /// Download a session log archive (GET /api/session.export?sessionId=…).
    public func exportSession(sessionId: String) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api").appendingPathComponent("session.export"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
        guard let url = components?.url else { throw DshError.badWebSocketURL }
        var request = URLRequest(url: url)
        await authorize(&request)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw DshError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// Answer a server-request (approval / question). rpcId must echo the
    /// requesting frame's envelope id; `value` is the domain payload.
    public func respond(rpcId: String, value: JSONValue) async throws {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("respond")
        var request = URLRequest(url: url)
        await authorize(&request)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(ClientResponse(rpcId: rpcId, value: value))
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw DshError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Downlink-only stream of mux frames (session events, approvals, questions, ...).
    public func muxEvents() -> AsyncThrowingStream<ServerRequest, Error> {
        events(path: "events.mux")
    }

    /// Downlink-only stream of host frames (session added/removed/status, workspaces, ...).
    public func hostEvents() -> AsyncThrowingStream<ServerRequest, Error> {
        events(path: "events.host")
    }

    private func events(path: String) -> AsyncThrowingStream<ServerRequest, Error> {
        AsyncThrowingStream { continuation in
            let apiURL = baseURL
                .appendingPathComponent("api")
                .appendingPathComponent(path)
            guard var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
                continuation.finish(throwing: DshError.badWebSocketURL)
                return
            }
            components.scheme = (baseURL.scheme == "https") ? "wss" : "ws"
            guard let wsURL = components.url else {
                continuation.finish(throwing: DshError.badWebSocketURL)
                return
            }

            let receiver = Task {
                var request = URLRequest(url: wsURL)
                await authorize(&request)
                let socket = session.webSocketTask(with: request)
                socket.resume()
                defer { socket.cancel(with: .goingAway, reason: nil) }
                let decoder = JSONDecoder()
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        if case .string(let text) = message,
                           let data = text.data(using: .utf8),
                           let frame = try? decoder.decode(ServerRequest.self, from: data) {
                            continuation.yield(frame)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                receiver.cancel()
            }
        }
    }
}
