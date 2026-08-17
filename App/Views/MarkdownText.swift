import SwiftUI
import UIKit

private func markdownInline(_ s: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: false,
        interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
}

/// Lightweight, dependency-free SwiftUI markdown renderer (adapted from Pharos).
/// Apple's AttributedString(markdown:) handles inline marks; this view owns block
/// layout: headings, bullet/numbered lists, fenced code blocks, GFM tables, paragraphs.
struct MarkdownText: View {
    let text: String
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    private enum Block {
        case heading(level: Int, text: String)
        case bullets([String])
        case ordered([String])
        case code(String)
        case table(headers: [String], rows: [[String]])
        case paragraph(String)
    }

    private var blocks: [Block] {
        let fence = "\u{60}\u{60}\u{60}"
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var result: [Block] = []
        var i = 0

        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        func isBullet(_ s: String) -> Bool { trimmed(s).hasPrefix("- ") || trimmed(s).hasPrefix("* ") }
        func isOrdered(_ s: String) -> Bool {
            trimmed(s).range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil
        }
        func isDelimiterRow(_ s: String) -> Bool {
            let cells = s.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let meaningful = cells.filter { !$0.isEmpty }
            guard !meaningful.isEmpty else { return false }
            return meaningful.allSatisfy { $0.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil }
        }
        func parseTableRow(_ s: String) -> [String] {
            var cells = s.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.first?.isEmpty == true { cells.removeFirst() }
            if cells.last?.isEmpty == true { cells.removeLast() }
            return cells
        }

        while i < lines.count {
            let line = lines[i]
            let t = trimmed(line)

            if t.isEmpty { i += 1; continue }

            if t.hasPrefix(fence) {
                var body: [String] = []
                i += 1
                while i < lines.count, !trimmed(lines[i]).hasPrefix(fence) {
                    body.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 }
                result.append(.code(body.joined(separator: "\n")))
                continue
            }
            if let r = t.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let level = t.distance(from: t.startIndex, to: t.firstIndex(of: " ") ?? t.startIndex)
                result.append(.heading(level: min(level, 3), text: String(t[r.upperBound...])))
                i += 1
                continue
            }
            if isBullet(line) {
                var items: [String] = []
                while i < lines.count, isBullet(lines[i]) {
                    items.append(String(trimmed(lines[i]).dropFirst(2))); i += 1
                }
                result.append(.bullets(items))
                continue
            }
            if isOrdered(line) {
                var items: [String] = []
                while i < lines.count, isOrdered(lines[i]) {
                    let lt = trimmed(lines[i])
                    if let r = lt.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                        items.append(String(lt[r.upperBound...]))
                    }
                    i += 1
                }
                result.append(.ordered(items))
                continue
            }
            if t.contains("|"), i + 1 < lines.count, isDelimiterRow(trimmed(lines[i + 1])) {
                let headers = parseTableRow(t)
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let lt = trimmed(lines[i])
                    if lt.isEmpty || !lt.contains("|") { break }
                    rows.append(parseTableRow(lt))
                    i += 1
                }
                result.append(.table(headers: headers, rows: rows))
                continue
            }
            var para: [String] = []
            while i < lines.count {
                let lt = trimmed(lines[i])
                if lt.isEmpty || lt.hasPrefix(fence) || isBullet(lines[i]) || isOrdered(lines[i])
                    || (lt.contains("|") && i + 1 < lines.count && isDelimiterRow(trimmed(lines[i + 1])))
                    || lt.range(of: #"^#{1,6}\s+"#, options: .regularExpression) != nil { break }
                para.append(lines[i]); i += 1
            }
            result.append(.paragraph(para.joined(separator: "\n")))
        }
        return result
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.weight(.semibold)
        default: return .headline.weight(.semibold)
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let s):
            Text(markdownInline(s))
                .font(headingFont(level))
                .padding(.top, 2)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(accent).frame(width: 5, height: 5).padding(.top, 6)
                        Text(markdownInline(item)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

        case .ordered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).").font(.body.monospacedDigit()).foregroundStyle(accent)
                        Text(markdownInline(item)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }

        case .code(let s):
            CodeBlock(text: s)

        case .table(let headers, let rows):
            TableBlock(headers: headers, rows: rows)

        case .paragraph(let s):
            Text(markdownInline(s))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TableBlock: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                        Text(markdownInline(h))
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color.secondary.opacity(0.14))

                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(markdownInline(cell))
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(i % 2 == 1 ? Color.secondary.opacity(0.06) : Color.clear)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}

private struct CodeBlock: View {
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("code").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
    }
}
