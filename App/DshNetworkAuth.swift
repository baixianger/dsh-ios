import Foundation
import Security

struct DshNetworkPairingResult: Decodable, Sendable {
    let hostId: String
    let name: String
    let accessToken: String
    let accessExpiresAt: Double
    let refreshToken: String
}

private struct StoredNetworkCredential: Codable, Sendable {
    var accessToken: String
    var accessExpiresAt: Double
    var refreshToken: String
}

private struct RefreshResponse: Decodable {
    let accessToken: String
    let accessExpiresAt: Double
    let refreshToken: String
}

enum DshNetworkAuthError: LocalizedError {
    case invalidPairingURL
    case rejected(Int)
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .invalidPairingURL: "无效的 DSH 配对二维码"
        case .rejected(let status): "配对被 DSH 主机拒绝（HTTP \(status)）"
        case .missingCredential: "设备凭据不存在，请重新扫码配对"
        }
    }
}

actor DshNetworkAuth {
    static let shared = DshNetworkAuth()
    private let service = "com.baixianger.dshios.network"

    func pair(scannedURL: URL) async throws -> (baseURL: URL, result: DshNetworkPairingResult) {
        let pairingURL = try Self.normalizedPairingURL(from: scannedURL)
        guard let components = URLComponents(url: pairingURL, resolvingAgainstBaseURL: false),
              components.path == "/dsh-network/connect",
              let ticket = pairingValue(named: "t", legacyName: "ticket", in: components),
              !ticket.isEmpty,
              var base = components.url else {
            throw DshNetworkAuthError.invalidPairingURL
        }
        let expectedHostID = pairingValue(named: "h", legacyName: "hostId", in: components)
        var baseComponents = URLComponents(url: base, resolvingAgainstBaseURL: false)
        baseComponents?.path = ""
        baseComponents?.query = nil
        baseComponents?.fragment = nil
        guard let cleanBase = baseComponents?.url else { throw DshNetworkAuthError.invalidPairingURL }
        base = cleanBase

        var request = URLRequest(url: base.appendingPathComponent("dsh-network").appendingPathComponent("pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var pairingBody = ["ticket": ticket, "deviceName": "DSH iOS"]
        if let expectedHostID { pairingBody["hostId"] = expectedHostID }
        request.httpBody = try JSONEncoder().encode(pairingBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw DshNetworkAuthError.rejected(status) }
        let result = try JSONDecoder().decode(DshNetworkPairingResult.self, from: data)
        guard expectedHostID == nil || result.hostId == expectedHostID else {
            throw DshNetworkAuthError.invalidPairingURL
        }
        try save(StoredNetworkCredential(
            accessToken: result.accessToken,
            accessExpiresAt: result.accessExpiresAt,
            refreshToken: result.refreshToken
        ), key: result.hostId)
        return (base, result)
    }

    nonisolated static func normalizedPairingURL(from url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "dsh" else { return url }
        guard url.host?.lowercased() == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let ticket = fragmentValue(named: "t", in: components), !ticket.isEmpty,
              let hostID = fragmentValue(named: "h", in: components), !hostID.isEmpty,
              let originValue = fragmentValue(named: "u", in: components),
              let origin = URL(string: originValue),
              ["http", "https"].contains(origin.scheme?.lowercased() ?? ""),
              origin.host != nil,
              origin.user == nil,
              origin.password == nil else {
            throw DshNetworkAuthError.invalidPairingURL
        }
        var pairing = URLComponents(url: origin, resolvingAgainstBaseURL: false)
        pairing?.path = "/dsh-network/connect"
        pairing?.query = nil
        var fragment = URLComponents()
        fragment.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "t", value: ticket),
            URLQueryItem(name: "h", value: hostID)
        ]
        pairing?.percentEncodedFragment = fragment.percentEncodedQuery
        guard let pairingURL = pairing?.url else { throw DshNetworkAuthError.invalidPairingURL }
        return pairingURL
    }

    private nonisolated static func fragmentValue(named name: String, in components: URLComponents) -> String? {
        guard let fragment = components.fragment else { return nil }
        var fragmentComponents = URLComponents()
        fragmentComponents.query = fragment
        return fragmentComponents.queryItems?.first(where: { $0.name == name })?.value
    }

    private func pairingValue(named name: String, legacyName: String, in components: URLComponents) -> String? {
        if let value = Self.fragmentValue(named: name, in: components) { return value }
        return components.queryItems?.first(where: { $0.name == legacyName })?.value
    }

    func authorization(for key: String, baseURL: URL) async -> String? {
        guard var credential = try? load(key: key) else { return nil }
        if credential.accessExpiresAt > Date().timeIntervalSince1970 * 1000 + 60_000 {
            return "Bearer \(credential.accessToken)"
        }
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("dsh-network").appendingPathComponent("refresh"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(["refreshToken": credential.refreshToken])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
            credential = StoredNetworkCredential(
                accessToken: refreshed.accessToken,
                accessExpiresAt: refreshed.accessExpiresAt,
                refreshToken: refreshed.refreshToken
            )
            try save(credential, key: key)
            return "Bearer \(credential.accessToken)"
        } catch {
            return nil
        }
    }

    func remove(key: String) {
        SecItemDelete(query(key: key) as CFDictionary)
    }

    private func load(key: String) throws -> StoredNetworkCredential {
        var query = query(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { throw DshNetworkAuthError.missingCredential }
        return try JSONDecoder().decode(StoredNetworkCredential.self, from: data)
    }

    private func save(_ credential: StoredNetworkCredential, key: String) throws {
        let data = try JSONEncoder().encode(credential)
        let base = query(key: key)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(insertStatus)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func query(key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
}
