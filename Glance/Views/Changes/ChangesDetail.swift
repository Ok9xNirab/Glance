//
//  ChangesDetail.swift
//  Glance
//

import SwiftUI

struct ChangesDetail: View {
    let changes: ChangesModel
    @Environment(AppModel.self) private var model
    @Environment(\.glanceAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            if let file = changes.selectedFile {
                toolbar(for: file)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        DiffHunksView(hunks: file.diff.hunks ?? [], layout: model.diffLayout, actions: hunkActions(for: file))
                    }
                }
                .id(file.id)
            } else {
                TopBar {}
                PaneMessage("Nothing to review in \(model.previewedBranch?.name ?? model.currentWorktree.name).")
            }
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
    }

    private func toolbar(for file: ChangedFile) -> some View {
        let isViewed = changes.isViewed(file)
        return TopBar(spacing: 4) {
            HStack(spacing: 0) {
                IconButton("chevron.left", help: "Previous File (K)", action: changes.selectPrevious)
                IconButton("chevron.right", help: "Next File (J)", action: changes.selectNext)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(Text(file.diff.directory).foregroundStyle(Palette.secondaryText))\(Text(file.diff.name).fontWeight(.semibold))")
                    .font(.mono(12.5))
                    .lineLimit(1)
                    .truncationMode(.head)
                fileSummary(file)
            }
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            DiffLayoutPicker()
            ToolbarSeparator()
            IconButton(
                isViewed ? "checkmark.circle.fill" : "checkmark.circle",
                help: "Mark as Viewed (V)",
                tint: isViewed ? accent : nil,
                action: changes.toggleViewedForSelection
            )
            CopyForAgentButton()
        }
    }

    private func hunkActions(for file: ChangedFile) -> HunkActions? {
        guard !changes.isReadOnly else { return nil }
        return HunkActions(
            isStaged: { changes.isStaged(hunk: $0, in: file) },
            toggleStaged: { changes.toggleStaged(hunk: $0, in: file) },
            discard: { changes.discard(hunk: $0, in: file) },
            discardsFile: file.diff.status == .added
        )
    }

    private func fileSummary(_ file: ChangedFile) -> some View {
        HStack(spacing: 6) {
            Text("\(file.diff.status.label) ·")
            LineStats(additions: file.diff.additions, deletions: file.diff.deletions)
            Text("· \(changes.selectedPosition ?? 0) of \(changes.files.count)")
            if let ago = file.agentEditedAgo {
                HStack(spacing: 5) {
                    Text("·")
                    AgentDot()
                    Text("Agent edited \(ago) ago")
                }
                .foregroundStyle(Palette.agent)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.secondaryText)
        .lineLimit(1)
    }

    private var statusBar: some View {
        let worktree = model.currentWorktree
        return StatusBar {
            if case let .branch(name, base) = changes.source {
                Text("Comparing \(Text(name).font(.mono(11))) with \(Text(base).font(.mono(11)))")
                Text("Double-click the branch to check it out")
            } else if worktree.isAgentActive {
                HStack(spacing: 6) {
                    AgentDot()
                    Text("Watching for changes")
                }
                .foregroundStyle(Palette.agent)
            } else {
                Text("Up to date")
            }
            if !changes.isReadOnly {
                Text(worktree.path).font(.mono(11))
                if let upstream = changes.upstream {
                    Text("↑\(upstream.ahead) ↓\(upstream.behind)")
                }
            }
            Spacer(minLength: 0)
            ShortcutHint(keys: ["J", "K"], label: "files")
            ShortcutHint(keys: ["V"], label: "viewed")
            ShortcutHint(keys: ["⌥S"], label: "split")
        }
    }
}
