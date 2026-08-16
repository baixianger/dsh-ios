import SwiftUI

struct QuestionCard: View {
    @EnvironmentObject private var model: AppModel
    let wait: QuestionWait
    @State private var selections: [String: Set<String>] = [:]

    private var questions: [JSONValue] { wait.payload["questions"]?.array ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("请回答", systemImage: "questionmark.circle")
                .font(.headline)
            ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
                questionView(q)
            }
            Button("提交") { submit() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func questionView(_ q: JSONValue) -> some View {
        let id = q["id"]?.string ?? ""
        let text = q["question"]?.string ?? ""
        let options = q["options"]?.array ?? []
        let multi = q["multi_select"]?.bool ?? false
        let selected = selections[id] ?? []
        return VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                MarkdownText(text: text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let label = opt["label"]?.string ?? ""
                let isOn = selected.contains(label)
                Button {
                    toggle(id: id, label: label, multi: multi)
                } label: {
                    HStack {
                        Image(systemName: isOn ? (multi ? "checkmark.square.fill" : "largecircle.fill.circle")
                                              : (multi ? "square" : "circle"))
                        Text(label).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(id: String, label: String, multi: Bool) {
        var current = selections[id] ?? []
        if multi {
            if current.contains(label) { current.remove(label) } else { current.insert(label) }
        } else {
            current = [label]
        }
        selections[id] = current
    }

    private func submit() {
        let answers = questions.map { q -> JSONValue in
            let id = q["id"]?.string ?? ""
            let selected = Array(selections[id] ?? []).map { JSONValue.string($0) }
            return .object(["id": .string(id), "selected": .array(selected)])
        }
        let value = JSONValue.object([
            "sessionId": .string(wait.sessionId),
            "answer": .object(["answers": .array(answers)]),
        ])
        Task { try? await model.client.respond(rpcId: wait.rpcId, value: value) }
    }
}
