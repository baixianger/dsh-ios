import XCTest
@testable import DshApp

final class DshServerAliasTests: XCTestCase {
    func testAliasOverridesServerNameLocally() {
        let server = DshServer(name: "mac-mini.tailnet", alias: "家庭 Mac mini", baseURLString: "https://mac-mini.example")
        XCTAssertEqual(server.displayName, "家庭 Mac mini")
    }

    func testLegacyStoredServerWithoutAliasStillDecodes() throws {
        let data = Data(#"{"name":"Mac mini","baseURLString":"https://mac-mini.example"}"#.utf8)
        let server = try JSONDecoder().decode(DshServer.self, from: data)
        XCTAssertNil(server.alias)
        XCTAssertEqual(server.displayName, "Mac mini")
    }

    func testBlankAliasFallsBackToServerName() {
        let server = DshServer(name: "Mac mini", alias: "   ", baseURLString: "https://mac-mini.example")
        XCTAssertEqual(server.displayName, "Mac mini")
    }
}

final class ServerOnboardingFlowTests: XCTestCase {
    func testFlowAdvancesAcrossAllConnectionSteps() {
        var flow = ServerOnboardingFlowState()
        XCTAssertEqual(flow.step, .server)
        XCTAssertFalse(flow.isLastStep)

        flow.advance()
        XCTAssertEqual(flow.step, .network)
        XCTAssertFalse(flow.isLastStep)

        flow.advance()
        XCTAssertEqual(flow.step, .pair)
        XCTAssertTrue(flow.isLastStep)

        flow.advance()
        XCTAssertEqual(flow.step, .pair)
    }
}
