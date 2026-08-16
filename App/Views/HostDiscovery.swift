import Foundation

struct DiscoveredHost: Identifiable {
    let id: String
    let baseURL: URL
    let label: String
    let model: String?
    let cwd: String?

    init(baseURL: URL, label: String, info: HostInfo?) {
        self.id = baseURL.absoluteString
        self.baseURL = baseURL
        self.label = label
        self.model = info?.model
        self.cwd = info?.cwd
    }
}

struct HostDiscovery {
    // Candidate endpoints: tailscale serve (https MagicDNS) and the local reverse proxy (http tailnet IP).
    static let candidates: [(label: String, url: String)] = [
        ("macbook-air", "http://macbook-air.tail849fa3.ts.net:8080"),
        ("mac-mini", "http://mac-mini.tail849fa3.ts.net:8080"),
        ("macbook-air (IP)", "http://100.91.91.43:8080"),
        ("mac-mini (IP)", "http://100.123.131.117:8080"),
    ]

    static func discover() async -> [DiscoveredHost] {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        let session = URLSession(configuration: config)

        var results: [DiscoveredHost] = []
        for candidate in candidates {
            guard let url = URL(string: candidate.url) else { continue }
            if let info = await probe(url: url, session: session) {
                results.append(DiscoveredHost(baseURL: url, label: candidate.label, info: info))
            }
        }
        return results
    }

    static func probe(url: URL, session: URLSession) async -> HostInfo? {
        var request = URLRequest(url: url.appendingPathComponent("api").appendingPathComponent("host.describe"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONEncoder().encode(ClientRequest(method: "host.describe", payload: .object([:])))
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let envelope = try JSONDecoder().decode(ServerResponse.self, from: data)
            guard envelope.result.ok, let value = envelope.result.value else { return nil }
            let d = try JSONEncoder().encode(value)
            return try? JSONDecoder().decode(HostInfo.self, from: d)
        } catch {
            return nil
        }
    }
}
