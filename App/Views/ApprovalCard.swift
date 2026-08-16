import SwiftUI

struct ApprovalCard: View {
    @EnvironmentObject private var model: AppModel
    let wait: ApprovalWait

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("需要审批", systemImage: "hand.raised")
                .font(.headline)
            Text("工具: \(wait.toolName)")
                .font(.subheadline)
            HStack {
                Button("允许一次") { respond("allowed-once") }
                    .buttonStyle(.borderedProminent)
                Button("拒绝") { respond("rejected") }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
    }

    private func respond(_ outcome: String) {
        let value = JSONValue.object([
            "sessionId": .string(wait.sessionId),
            "approvalId": .string(wait.approvalId),
            "outcome": .string(outcome),
        ])
        Task { try? await model.client.respond(rpcId: wait.rpcId, value: value) }
    }
}
