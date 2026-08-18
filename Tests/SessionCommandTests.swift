import XCTest
@testable import DshApp

final class SessionCommandTests: XCTestCase {
    func testParsesHostCommandInputHintAndInsertion() throws {
        let json = JSONValue.object([
            "name": .string("plan"),
            "description": .string("Enter or leave plan mode"),
            "input": .object(["hint": .string("[off|message]")]),
        ])

        let command = try XCTUnwrap(SessionCommand(json: json))

        XCTAssertEqual(command.name, "plan")
        XCTAssertEqual(command.description, "Enter or leave plan mode")
        XCTAssertEqual(command.inputHint, "[off|message]")
        XCTAssertEqual(command.insertion, "/plan ")
    }

    func testCommandWithoutInputDoesNotAddSpace() throws {
        let json = JSONValue.object([
            "name": .string("/compact"),
            "description": .string("Compact older conversation history"),
        ])

        let command = try XCTUnwrap(SessionCommand(json: json))

        XCTAssertEqual(command.name, "compact")
        XCTAssertNil(command.inputHint)
        XCTAssertEqual(command.insertion, "/compact")
    }

    func testRejectsCommandWithoutName() {
        XCTAssertNil(SessionCommand(json: .object(["description": .string("missing name")])))
    }
}
