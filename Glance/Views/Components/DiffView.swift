//
//  DiffView.swift
//  Glance
//

import SwiftUI

/// Hunks as pinned sections. Place inside a `LazyVStack(pinnedViews: .sectionHeaders)` in a `ScrollView`.
struct DiffHunksView: View {
    let hunks: [DiffHunk]
    let layout: DiffLayout
    var showsHunkActions = false

    var body: some View {
        ForEach(hunks) { hunk in
            Section {
                switch layout {
                case .unified:
                    ForEach(hunk.lines) { UnifiedDiffRow(line: $0) }
                case .split:
                    ForEach(hunk.splitRows) { SplitDiffRow(row: $0) }
                }
                Hairline()
            } header: {
                HunkHeader(hunk: hunk, showsActions: showsHunkActions)
            }
        }
    }
}

private struct HunkHeader: View {
    let hunk: DiffHunk
    let showsActions: Bool
    @Environment(\.glanceAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(hunk.header)
            Text(hunk.context)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsActions {
                HStack(spacing: 6) {
                    Button("Stage Hunk") {}
                    Button("Discard") {}
                }
                .buttonStyle(BezelButtonStyle(height: 22))
            }
        }
        .font(.mono(12))
        .foregroundStyle(Palette.secondaryText)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(minHeight: 30)
        .background {
            ZStack {
                Palette.window
                accent.opacity(colorScheme == .dark ? 0.14 : 0.07)
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
    }
}

private struct UnifiedDiffRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            LineNumber(number: line.oldNumber, kind: line.kind)
            LineNumber(number: line.newNumber, kind: line.kind)
            DiffCode(kind: line.kind, text: line.text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(line.kind.rowBackground)
    }
}

private struct SplitDiffRow: View {
    let row: SplitRow

    var body: some View {
        HStack(spacing: 0) {
            half(row.left)
            Hairline(axis: .vertical)
            half(row.right)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func half(_ cell: SplitRow.Cell?) -> some View {
        if let cell {
            HStack(alignment: .top, spacing: 0) {
                LineNumber(number: cell.number, kind: cell.kind)
                DiffCode(kind: cell.kind, text: cell.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cell.kind.rowBackground)
        } else {
            Palette.emptyCell.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LineNumber: View {
    let number: Int?
    let kind: DiffLine.Kind

    var body: some View {
        Text(number.map(String.init) ?? "")
            .font(.mono(12))
            .foregroundStyle(Palette.gutter)
            .padding(.trailing, 10)
            .padding(.vertical, 3)
            .frame(width: 50, alignment: .trailing)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(kind.gutterBackground)
            .accessibilityHidden(true)
    }
}

private struct DiffCode: View {
    let kind: DiffLine.Kind
    let text: String

    var body: some View {
        Text(kind.sign)
            .font(.mono(12, weight: .semibold))
            .foregroundStyle(kind.signColor)
            .frame(width: 22)
            .padding(.vertical, 3)
        Text(text.isEmpty ? " " : text)
            .font(.mono(12))
            .foregroundStyle(Palette.code)
            .lineSpacing(5)
            .padding(.vertical, 3)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

private extension DiffLine.Kind {
    var rowBackground: Color {
        switch self {
        case .context: .clear
        case .addition: Palette.additionBackground
        case .deletion: Palette.deletionBackground
        }
    }

    var gutterBackground: Color {
        switch self {
        case .context: .clear
        case .addition: Palette.additionGutter
        case .deletion: Palette.deletionGutter
        }
    }

    var signColor: Color {
        switch self {
        case .context: .clear
        case .addition: Palette.additionText
        case .deletion: Palette.deletionText
        }
    }
}
