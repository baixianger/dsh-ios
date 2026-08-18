import XCTest
@testable import DshApp

final class DshNetworkAuthTests: XCTestCase {
    func testConvertsAppHandoffIntoHostBoundHTTPSPairingURL() throws {
        let handoff = try XCTUnwrap(URL(string: "dsh://pair#v=1&t=secret-ticket&h=host-123&u=https%3A%2F%2Fserver.example"))
        let pairing = try DshNetworkAuth.normalizedPairingURL(from: handoff)
        let components = try XCTUnwrap(URLComponents(url: pairing, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "server.example")
        XCTAssertEqual(components.path, "/dsh-network/connect")
        var fragment = URLComponents()
        fragment.query = components.fragment
        let values = Dictionary(uniqueKeysWithValues: (fragment.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(values["t"]!, "secret-ticket")
        XCTAssertEqual(values["h"]!, "host-123")
    }

    func testRejectsHandoffWithoutHostIdentity() throws {
        let handoff = try XCTUnwrap(URL(string: "dsh://pair#v=1&t=secret-ticket&u=https%3A%2F%2Fserver.example"))
        XCTAssertThrowsError(try DshNetworkAuth.normalizedPairingURL(from: handoff))
    }

    func testLeavesUniversalHTTPSPairingURLUnchanged() throws {
        let universal = try XCTUnwrap(URL(string: "https://server.example/dsh-network/connect#v=1&t=secret&h=host"))
        XCTAssertEqual(try DshNetworkAuth.normalizedPairingURL(from: universal), universal)
    }
}
