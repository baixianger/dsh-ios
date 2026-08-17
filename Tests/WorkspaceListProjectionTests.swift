import XCTest
@testable import DshApp

final class WorkspaceListProjectionTests: XCTestCase {
    func testArchivedSessionIdsAreKeptSeparateFromWorkspaceMembership() throws {
        let sessionId = "session-archived"
        let json = JSONValue.object([
            "items": .array([
                .object([
                    "workspaceId": .string("workspace-1"),
                    "path": .string("/tmp/workspace"),
                    "title": .string("Workspace"),
                    "sessionIds": .array([.string(sessionId)]),
                ]),
            ]),
            "archivedSessionIds": .array([.string(sessionId)]),
        ])

        let projection = WorkspaceListProjection(json: json)

        XCTAssertEqual(projection.workspaces.count, 1)
        XCTAssertEqual(projection.workspaces[0].sessionIds, [sessionId])
        XCTAssertEqual(projection.archivedSessionIds, [sessionId])
    }
}
