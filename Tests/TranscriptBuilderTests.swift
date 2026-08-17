import XCTest
@testable import DshApp

final class TranscriptBuilderTests: XCTestCase {
    func testReasoningAndToolsBecomeOneActivityBeforeResponse() {
        let assistant = ChatItem(
            id: "assistant-1",
            role: .assistant,
            text: "最终回答",
            reasoning: "分析过程",
            messageId: "message-1"
        )
        let toolCall = ChatItem(
            id: "tool-1",
            role: .tool,
            text: "",
            toolName: "read",
            toolArgs: "README.md"
        )
        let toolResult = ChatItem(
            id: "tool-result-1",
            role: .tool,
            text: "contents",
            isToolResult: true
        )

        let entries = TranscriptBuilder.build(from: [assistant, toolCall, toolResult])

        XCTAssertEqual(entries.count, 2)
        guard case .activity(let id, let reasoning, let tools) = entries[0] else {
            return XCTFail("Expected a unified activity entry")
        }
        XCTAssertEqual(id, "activity-assistant-1")
        XCTAssertEqual(reasoning, "分析过程")
        XCTAssertEqual(tools.map(\.id), ["tool-1", "tool-result-1"])

        guard case .message(let response) = entries[1] else {
            return XCTFail("Expected the assistant response after the activity")
        }
        XCTAssertEqual(response.text, "最终回答")
        XCTAssertNil(response.reasoning)
        XCTAssertEqual(response.messageId, "message-1")
    }

    func testReasoningWithoutToolsStaysOnMessage() {
        let assistant = ChatItem(
            id: "assistant-1",
            role: .assistant,
            text: "回答",
            reasoning: "分析"
        )

        let entries = TranscriptBuilder.build(from: [assistant])

        XCTAssertEqual(entries.count, 1)
        guard case .message(let message) = entries[0] else {
            return XCTFail("Expected the original message")
        }
        XCTAssertEqual(message.reasoning, "分析")
    }

    func testToolRunWithoutReasoningBecomesActivity() {
        let toolCall = ChatItem(
            id: "tool-1",
            role: .tool,
            text: "",
            toolName: "read"
        )
        let toolResult = ChatItem(
            id: "tool-result-1",
            role: .tool,
            text: "contents",
            isToolResult: true
        )

        let entries = TranscriptBuilder.build(from: [toolCall, toolResult])

        XCTAssertEqual(entries.count, 1)
        guard case .activity(let id, let reasoning, let tools) = entries[0] else {
            return XCTFail("Expected a tool activity entry")
        }
        XCTAssertEqual(id, "tools-tool-1")
        XCTAssertNil(reasoning)
        XCTAssertEqual(tools.count, 2)
    }

    func testReasoningOnlyAssistantIsOmittedWhenUnifiedWithTools() {
        let assistant = ChatItem(
            id: "assistant-1",
            role: .assistant,
            text: "",
            reasoning: "分析"
        )
        let toolCall = ChatItem(
            id: "tool-1",
            role: .tool,
            text: "",
            toolName: "read"
        )

        let entries = TranscriptBuilder.build(from: [assistant, toolCall])

        XCTAssertEqual(entries.count, 1)
        guard case .activity(_, let reasoning, _) = entries[0] else {
            return XCTFail("Expected a unified activity entry")
        }
        XCTAssertEqual(reasoning, "分析")
    }
}
