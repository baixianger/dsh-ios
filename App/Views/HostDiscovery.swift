import Foundation

struct DiscoveredHost: Identifiable {
    var id: String { hostID ?? baseURL.absoluteString }
    let baseURL: URL
    let label: String
    let hostID: String?
    let model: String?
    let cwd: String?
    let requiresPairing: Bool

    init(baseURL: URL, label: String, info: HostInfo?, hostID: String? = nil, requiresPairing: Bool = false) {
        self.baseURL = baseURL
        self.label = label
        self.hostID = hostID ?? info?.hostId
        self.model = info?.model
        self.cwd = info?.cwd
        self.requiresPairing = requiresPairing
    }
}

private struct NetworkGatewayInfo: Decodable {
    let hostId: String
    let name: String
    let requiresPairing: Bool
}

struct HostDiscovery {
    static func discover() async -> [DiscoveredHost] {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        let session = URLSession(configuration: config)

        // Bonjour is intentionally limited to the current LAN. Tailnet and other
        // routed addresses are user-configured in Settings rather than guessed.
        let discovered = await BonjourDiscovery.discover()

        var results: [DiscoveredHost] = []
        for (label, url) in discovered {
            if let gateway = await probeGateway(url: url, session: session) {
                results.append(DiscoveredHost(
                    baseURL: url,
                    label: gateway.name.isEmpty ? label : gateway.name,
                    info: nil,
                    hostID: gateway.hostId,
                    requiresPairing: gateway.requiresPairing
                ))
            } else if let info = await probe(url: url, session: session) {
                results.append(DiscoveredHost(baseURL: url, label: label, info: info))
            }
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }

    private static func probeGateway(url: URL, session: URLSession) async -> NetworkGatewayInfo? {
        do {
            let endpoint = url.appendingPathComponent("dsh-network").appendingPathComponent("info")
            let (data, response) = try await session.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(NetworkGatewayInfo.self, from: data)
        } catch {
            return nil
        }
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

private final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var continuation: CheckedContinuation<[(String, URL)], Never>?
    private var timeoutTask: Task<Void, Never>?

    static func discover() async -> [(String, URL)] {
        await withCheckedContinuation { continuation in
            let discovery = BonjourDiscovery()
            discovery.start(continuation: continuation)
        }
    }

    private func start(continuation: CheckedContinuation<[(String, URL)], Never>) {
        self.continuation = continuation
        browser.delegate = self
        browser.searchForServices(ofType: "_dsh._tcp.", inDomain: "local.")
        timeoutTask = Task { [self] in
            try? await Task.sleep(for: .seconds(3))
            finish()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 2)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {}

    private func finish() {
        timeoutTask?.cancel()
        browser.stop()
        let endpoints = services.compactMap { service -> (String, URL)? in
            guard let host = service.hostName, service.port > 0,
                  let url = URL(string: "http://\(host):\(service.port)") else { return nil }
            return (service.name, url)
        }
        continuation?.resume(returning: endpoints)
        continuation = nil
    }
}
