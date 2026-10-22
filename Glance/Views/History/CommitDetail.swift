//
//  CommitDetail.swift
//  Glance
//

import SwiftUI

struct CommitDetail: View {
    @Bindable var history: HistoryModel
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let commit = history.selectedCommit {
                toolbar(for: commit)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        CommitSummary(commit: commit, selectedFileIndex: $history.selectedFileIndex)
                        if let hunks = history.selectedFile?.hunks {
                            DiffHunksView(hunks: hunks, layout: model.diffLayout)
                        } else if !commit.files.isEmpty {
                            Text("The diff for this commit loads when it is selected.")
                                .foregroundStyle(Palette.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 48)
                        }
                    }
                }
                .id(commit.id)
            } else {
                TopBar {}
                PaneMessage("No commit selected.")
            }
            StatusBar {
                Text("\(history.unpushedCount) commits not pushed")
                Text(model.currentWorktree.path).font(.mono(11))
                Spacer(minLength: 0)
                ShortcutHint(keys: ["↑", "↓"], label: "commits")
                ShortcutHint(keys: ["⌘C"], label: model.recentlyCopied == .sha ? "SHA copied" : "copy SHA")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
    }

    private func toolbar(for commit: Commit) -> some View {
        TopBar(spacing: 4, leading: 18) {
            Text(commit.title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            DiffLayoutPicker()
            ToolbarSeparator()
            CopyForAgentButton()
            Menu {
                Button("Revert Commit") {}
                Button("Cherry-Pick onto Current Branch") {}
                Button("Create Branch from Commit…") {}
                Divider()
                Button("Copy SHA") { model.copy(commit.sha, as: .sha) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Palette.secondaryText)
            .frame(width: 28, height: 28)
            .help("Revert, cherry-pick, create branch, copy SHA")
        }
    }
}

/// Commit message, metadata and the file tabs that pick which diff is shown below.
private struct CommitSummary: View {
    let commit: Commit
    @Binding var selectedFileIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(commit.title)
                .font(.system(size: 18, weight: .semibold))
                .textSelection(.enabled)
            if !commit.body.isEmpty {
                Text(commit.body)
                    .foregroundStyle(Palette.secondaryText)
                    .lineSpacing(3)
                    .frame(maxWidth: 680, alignment: .leading)
                    .textSelection(.enabled)
            }
            FlowLayout(spacing: 10) {
                HStack(spacing: 6) {
                    Avatar(author: commit.author, size: 20)
                    Text(commit.author.name).foregroundStyle(Palette.text)
                }
                if commit.isAgentCoAuthored {
                    AgentChip(title: "Co-authored by agent")
                }
                Text(commit.date)
                Text(commit.sha).font(.mono(12))
                Text("\(commit.files.count) files")
                LineStats(additions: commit.additions, deletions: commit.deletions)
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.secondaryText)

            if !commit.files.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(commit.files.enumerated()), id: \.element.id) { index, file in
                        CommitFileTab(file: file, isSelected: index == selectedFileIndex) {
                            selectedFileIndex = index
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

private struct CommitFileTab: View {
    let file: FileDiff
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                StatusBadge(status: file.status)
                Text("\(Text(file.directory).foregroundStyle(Palette.secondaryText))\(file.name)")
                    .font(.mono(12))
                LineStats(additions: file.additions, deletions: file.deletions)
            }
            .fontWeight(isSelected ? .semibold : .regular)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? .clear : Palette.separator)
            )
        }
        .buttonStyle(RowButtonStyle(fill: isSelected ? Palette.selection : nil))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
