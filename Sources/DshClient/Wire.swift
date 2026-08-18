import Foundation

/// C -> S unary envelope: POST /api/{method}.
public struct ClientRequest: Encodable, Sendable {
    public let type: String
    public let rpcId: String
    public let method: String
    public let payload: JSONValue

    public init(method: String, payload: JSONValue, rpcId: String = UUID().uuidString.lowercased()) {
        self.type = "client-request"
        self.rpcId = rpcId
        self.method = method
        self.payload = payload
    }
}

/// Business error body returned inside a server-response with ok:false.
public struct RpcError: Decodable, Error, Sendable, CustomStringConvertible {
    public let code: String
    public let message: String
    public let details: JSONValue?
    public var description: String { "RpcError(\(code)): \(message)" }
}

public struct RpcResult: Decodable, Sendable {
    public let ok: Bool
    public let value: JSONValue?
    public let error: RpcError?
}

/// S -> C unary envelope.
public struct ServerResponse: Decodable, Sendable {
    public let type: String
    public let rpcId: String
    public let result: RpcResult
}

/// S -> C frame envelope carried over the WebSocket event streams.
public struct ServerRequest: Decodable, Sendable {
    public let type: String
    public let rpcId: String
    public let method: String
    public let payload: JSONValue
}

/// C -> S response to a server-request (approval / question answer).
public struct ClientResponse: Encodable, Sendable {
    public let type: String
    public let rpcId: String
    public let result: ClientResult

    public init(rpcId: String, value: JSONValue) {
        self.type = "client-response"
        self.rpcId = rpcId
        self.result = ClientResult(ok: true, value: value)
    }
}

public struct ClientResult: Encodable, Sendable {
    public let ok: Bool
    public let value: JSONValue
}

public enum DshError: Error, CustomStringConvertible {
    case http(status: Int, body: String)
    case missingValue
    case badWebSocketURL

    public var description: String {
        switch self {
        case .http(let status, let body): return "HTTP \(status): \(body)"
        case .missingValue: return "server returned ok:true without a value"
        case .badWebSocketURL: return "could not build WebSocket URL"
        }
    }
}

/// host.describe value (typed example — the real app types every domain).
public struct HostInfo: Decodable, Sendable {
    public let hostId: String?
    public let version: String
    public let cwd: String
    public let provider: String?
    public let model: String?
    public let attachedSessions: Int
    public let canOpenPath: Bool
}
