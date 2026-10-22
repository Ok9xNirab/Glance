//
//  FileDiff.swift
//  Glance
//

import Foundation

/// A hunk as written in the sample data: a start position and lines prefixed with `+`, `-` or a space.
struct RawHunk {
    let oldStart: Int
    let newStart: Int
    var context = ""
    let lines: [String]
}

struct DiffLine: Identifiable {
    enum Kind {
        case context, addition, deletion

        var patchPrefix: String {
            switch self {
            case .context: " "
            case .addition: "+"
            case .deletion: "-"
            }
        }

        var sign: String {
            switch self {
            case .context: ""
            case .addition: "+"
            case .deletion: "−"
            }
        }
    }

    /// Unique across hunks, since all of a file's hunks share one lazy stack.
    let id: String
    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String
    var syntax: [SyntaxSpan] = []
}

/// One row of the side-by-side layout. A `nil` side renders as an empty cell.
struct SplitRow: Identifiable {
    struct Cell {
        let kind: DiffLine.Kind
        let number: Int?
        let text: String
        let syntax: [SyntaxSpan]
    }

    let id: String
    let left: Cell?
    let right: Cell?
}

struct DiffHunk: Identifiable {
    let id: Int
    let header: String
    let context: String
    let lines: [DiffLine]
    let splitRows: [SplitRow]
}

extension DiffHunk {
    init(id: Int, raw: RawHunk, language: SourceLanguage) {
        var old = raw.oldStart
        var new = raw.newStart
        var oldCount = 0
        var newCount = 0
        var lines: [DiffLine] = []

        for (index, rawLine) in raw.lines.enumerated() {
            let text = String(rawLine.dropFirst())
            switch rawLine.first {
            case "+":
                lines.append(DiffLine(id: "\(id):\(index)", kind: .addition, oldNumber: nil, newNumber: new, text: text))
                new += 1
                newCount += 1
            case "-":
                lines.append(DiffLine(id: "\(id):\(index)", kind: .deletion, oldNumber: old, newNumber: nil, text: text))
                old += 1
                oldCount += 1
            default:
                lines.append(DiffLine(id: "\(id):\(index)", kind: .context, oldNumber: old, newNumber: new, text: text))
                old += 1
                new += 1
                oldCount += 1
                newCount += 1
            }
        }

        Self.highlight(&lines, as: language)

        self.init(
            id: id,
            header: "@@ -\(raw.oldStart),\(oldCount) +\(raw.newStart),\(newCount) @@",
            context: raw.context,
            lines: lines,
            splitRows: Self.pairRows(lines, hunkID: id)
        )
    }

    /// Highlights the old side (context and deletions) and the new side (context and additions) as two
    /// continuous snippets, so each line is parsed with the lines around it.
    private static func highlight(_ lines: inout [DiffLine], as language: SourceLanguage) {
        let oldSide = lines.indices.filter { lines[$0].kind != .addition }
        let newSide = lines.indices.filter { lines[$0].kind != .deletion }
        let oldSpans = SyntaxHighlighter.spans(for: oldSide.map { lines[$0].text }, as: language)
        let newSpans = SyntaxHighlighter.spans(for: newSide.map { lines[$0].text }, as: language)
        for (index, spans) in zip(oldSide, oldSpans) where lines[index].kind == .deletion {
            lines[index].syntax = spans
        }
        for (index, spans) in zip(newSide, newSpans) {
            lines[index].syntax = spans
        }
    }

    /// Pairs each run of deletions with the additions that follow it, so replaced lines sit side by side.
    private static func pairRows(_ lines: [DiffLine], hunkID: Int) -> [SplitRow] {
        var rows: [SplitRow] = []
        var deletions: [DiffLine] = []
        var additions: [DiffLine] = []

        func flush() {
            for index in 0..<max(deletions.count, additions.count) {
                let deletion = index < deletions.count ? deletions[index] : nil
                let addition = index < additions.count ? additions[index] : nil
                rows.append(SplitRow(
                    id: "\(hunkID):\(rows.count)",
                    left: deletion.map { .init(kind: .deletion, number: $0.oldNumber, text: $0.text, syntax: $0.syntax) },
                    right: addition.map { .init(kind: .addition, number: $0.newNumber, text: $0.text, syntax: $0.syntax) }
                ))
            }
            deletions.removeAll()
            additions.removeAll()
        }

        for line in lines {
            switch line.kind {
            case .deletion:
                if !additions.isEmpty { flush() }
                deletions.append(line)
            case .addition:
                additions.append(line)
            case .context:
                flush()
                rows.append(SplitRow(
                    id: "\(hunkID):\(rows.count)",
                    left: .init(kind: .context, number: line.oldNumber, text: line.text, syntax: line.syntax),
                    right: .init(kind: .context, number: line.newNumber, text: line.text, syntax: line.syntax)
                ))
            }
        }
        flush()
        return rows
    }
}

struct FileDiff: Identifiable {
    let path: String
    let status: FileStatus
    /// `nil` when only the line counts are known and the diff hasn't been loaded.
    let hunks: [DiffHunk]?
    let additions: Int
    let deletions: Int

    var id: String { path }
    var directory: String { path.pathDirectory }
    var name: String { path.pathName }

    init(_ path: String, _ status: FileStatus, hunks rawHunks: [RawHunk]) {
        let language = SourceLanguage(path: path)
        let hunks = rawHunks.enumerated().map { DiffHunk(id: $0.offset, raw: $0.element, language: language) }
        let lines = hunks.flatMap(\.lines)
        self.path = path
        self.status = status
        self.hunks = hunks
        additions = lines.count { $0.kind == .addition }
        deletions = lines.count { $0.kind == .deletion }
    }

    init(_ path: String, _ status: FileStatus, additions: Int, deletions: Int) {
        self.path = path
        self.status = status
        hunks = nil
        self.additions = additions
        self.deletions = deletions
    }

    /// The path followed by a fenced unified diff, ready to paste into an agent prompt.
    var patch: String {
        let body = (hunks ?? []).map { hunk in
            let header = hunk.context.isEmpty ? hunk.header : "\(hunk.header) \(hunk.context)"
            return ([header] + hunk.lines.map { $0.kind.patchPrefix + $0.text }).joined(separator: "\n")
        }
        return "\(path)\n```diff\n\(body.joined(separator: "\n"))\n```"
    }
}
