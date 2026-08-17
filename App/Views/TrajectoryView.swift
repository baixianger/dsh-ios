import SwiftUI

struct TrajectorySheet: View {
    @ObservedObject var model: SessionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("dsh.trajectory.duration") private var usesRecordedDuration = false
    @State private var searchQuery = ""
    @State private var collapsedTurns: Set<String> = []
    @State private var callsCollapsed = false
    @State private var selectedRecord: TrajectoryRecord?

    private var filteredRecords: [TrajectoryRecord] {
        let terms = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return model.trajectoryRecords }
        return model.trajectoryRecords.filter { record in
            terms.allSatisfy { record.searchableText.contains($0) }
        }
    }

    private var turns: [TrajectoryTurn] {
        TrajectoryBuilder.group(filteredRecords)
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.trajectoryRecords.isEmpty {
                    ProgressView("正在加载轨迹…")
                } else if model.trajectoryRecords.isEmpty {
                    ContentUnavailableView {
                        Label("暂无轨迹", systemImage: "point.3.connected.trianglepath.dotted")
                    } description: {
                        Text("会话产生消息、模型请求或工具调用后，轨迹会显示在这里。")
                    }
                } else {
                    ledger
                }
            }
            .navigationTitle("轨迹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedRecord != nil },
                set: { if !$0 { selectedRecord = nil } }
            )) {
                if let selectedRecord {
                    TrajectoryRecordDetail(record: selectedRecord)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var ledger: some View {
        VStack(spacing: 0) {
            trajectoryToolbar

            TrajectoryTimelineStrip(
                records: filteredRecords,
                usesRecordedDuration: usesRecordedDuration,
                selectedId: selectedRecord?.id,
                onSelect: { selectedRecord = $0 }
            )
            .frame(height: 54)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if model.trajectoryHasMore {
                        Button {
                            Task { await model.loadOlderTrajectory() }
                        } label: {
                            HStack(spacing: 7) {
                                if model.isLoadingOlderTrajectory {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.up.to.line.compact")
                                }
                                Text(model.isLoadingOlderTrajectory ? "正在加载较早轨迹…" : "加载较早轨迹")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isLoadingOlderTrajectory)
                    }

                    ForEach(turns) { turn in
                        trajectoryTurn(turn)
                    }

                    if filteredRecords.isEmpty {
                        Text("没有匹配的轨迹记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    }
                }
            }
        }
    }

    private var trajectoryToolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                toolbarButton(
                    title: "Duration",
                    systemImage: "clock",
                    selected: usesRecordedDuration
                ) {
                    usesRecordedDuration.toggle()
                }

                toolbarButton(
                    title: "Turns",
                    systemImage: allTurnsCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                    selected: allTurnsCollapsed
                ) {
                    toggleAllTurns()
                }

                toolbarButton(
                    title: "Calls",
                    systemImage: "wrench.and.screwdriver",
                    selected: callsCollapsed
                ) {
                    callsCollapsed.toggle()
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("搜索", text: $searchQuery)
                        .font(.caption)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 96, maxWidth: 160, minHeight: 30, maxHeight: 30)
                .background(Color.dsSurfacePrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
        .padding(.bottom, 6)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("轨迹工具栏")
    }

    private func toolbarButton(
        title: LocalizedStringKey,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if horizontalSizeClass == .compact {
                    Image(systemName: systemImage)
                        .frame(width: 32)
                } else {
                    Label(title, systemImage: systemImage)
                        .padding(.horizontal, 7)
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(selected ? .primary : .secondary)
            .frame(height: 30)
            .background(selected ? Color.dsSurfaceSelected : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "已启用" : "已停用")
    }

    @ViewBuilder
    private func trajectoryTurn(_ turn: TrajectoryTurn) -> some View {
        let key = turn.id
        let isCollapsed = collapsedTurns.contains(key)
        let visible = callsCollapsed
            ? turn.records.filter { $0.kind != .tool && $0.kind != .subtool }
            : turn.records
        let hiddenCalls = turn.records.count - visible.count

        Section {
            if !isCollapsed {
                ForEach(visible) { record in
                    TrajectoryRecordRow(record: record, showsDuration: usesRecordedDuration) {
                        selectedRecord = record
                    }
                }
                if hiddenCalls > 0 {
                    Label("已折叠 \(hiddenCalls) 个调用", systemImage: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                }
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if isCollapsed { collapsedTurns.remove(key) }
                    else { collapsedTurns.insert(key) }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 12)
                    Text(turn.turn.map { "Turn \($0)" } ?? String(localized: "Session"))
                        .font(.caption.weight(.semibold))
                    Text("\(turn.records.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color(uiColor: .secondarySystemBackground))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var allTurnsCollapsed: Bool {
        !turns.isEmpty && turns.allSatisfy { collapsedTurns.contains($0.id) }
    }

    private func toggleAllTurns() {
        withAnimation(.easeInOut(duration: 0.16)) {
            if allTurnsCollapsed { collapsedTurns.removeAll() }
            else { collapsedTurns = Set(turns.map(\.id)) }
        }
    }
}

private struct TrajectoryRecordRow: View {
    let record: TrajectoryRecord
    let showsDuration: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(record.color)
                    .frame(width: 4, height: 25)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(record.displayTitle)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        if let step = record.step {
                            Text("Step \(step)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if !record.preview.isEmpty {
                        Text(record.preview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    if showsDuration {
                        Text(record.durationLabel)
                    } else {
                        Text("#\(record.seq)")
                    }
                    Text(record.timeLabel)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Divider().padding(.leading, 25)
    }
}

private struct TrajectoryTimelineStrip: View {
    let records: [TrajectoryRecord]
    let usesRecordedDuration: Bool
    let selectedId: String?
    let onSelect: (TrajectoryRecord) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 4) {
                ForEach(records) { record in
                    Button { onSelect(record) } label: {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(record.color.opacity(selectedId == nil || selectedId == record.id ? 0.9 : 0.24))
                            .frame(width: width(for: record), height: record.kind == .tool || record.kind == .subtool ? 10 : 14)
                            .overlay {
                                if selectedId == record.id {
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.dsAccentBlue, lineWidth: 2)
                                        .padding(-2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(record.displayTitle)
                    .accessibilityValue(record.durationLabel)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 54)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func width(for record: TrajectoryRecord) -> CGFloat {
        guard usesRecordedDuration, let ms = record.durationMilliseconds else { return 12 }
        return min(96, max(8, 8 + CGFloat(log10(max(1, ms))) * 15))
    }
}

private struct TrajectoryRecordDetail: View {
    let record: TrajectoryRecord

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Event", value: record.eventType)
                LabeledContent("Sequence", value: "\(record.seq)")
                if let turn = record.turn { LabeledContent("Turn", value: "\(turn)") }
                if let step = record.step { LabeledContent("Step", value: "\(step)") }
                LabeledContent("Duration", value: record.durationLabel)
                LabeledContent("Time", value: record.fullTimeLabel)
            }

            if !record.preview.isEmpty {
                Section("Preview") {
                    Text(record.preview)
                        .textSelection(.enabled)
                }
            }

            Section("Event data") {
                Text(record.data.prettyPrinted)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            if let view = record.view {
                Section("Host view") {
                    Text(view.prettyPrinted)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(record.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension TrajectoryRecord {
    var displayTitle: String {
        switch kind {
        case .user: return String(localized: "User message")
        case .assistant: return String(localized: "Assistant")
        case .context: return String(localized: "Request context")
        case .compaction: return String(localized: "Compaction")
        case .system: return String(localized: "Session ended")
        case .error: return String(localized: "Turn error")
        case .tool, .subtool: return title
        }
    }

    var color: Color {
        if isError { return .red }
        switch kind {
        case .user: return Color.dsAccentBlue
        case .assistant: return .purple
        case .tool, .subtool: return .orange
        case .context: return .green
        case .compaction: return .teal
        case .system: return .secondary
        case .error: return .red
        }
    }

    var durationLabel: String {
        guard let durationMilliseconds else { return "—" }
        return String(format: "%.0f ms", durationMilliseconds)
    }

    var timeLabel: String {
        Self.timeFormatter.string(from: Date(timeIntervalSince1970: time / 1_000))
    }

    var fullTimeLabel: String {
        Self.fullTimeFormatter.string(from: Date(timeIntervalSince1970: time / 1_000))
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let fullTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
