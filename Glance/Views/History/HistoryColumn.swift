//
//  HistoryColumn.swift
//  Glance
//

import SwiftUI

struct HistoryColumn: View {
    @Bindable var history: HistoryModel
    @Environment(AppModel.self) private var model

    var body: some View {
        ListColumn {
            VStack(spacing: 10) {
                ViewModePicker()
                SearchField("Message, author or SHA", text: $history.filter)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if !history.isLoaded {
                Spacer()
            } else if history.commits.isEmpty {
                PaneMessage("No commits yet.")
            } else if history.visibleCommits.isEmpty {
                PaneMessage("No commits match “\(history.filter)”")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(history.visibleCommits) { commit in
                            if commit.startsRemoteHistory, history.filter.isEmpty {
                                RemoteDivider(name: history.upstream ?? "pushed")
                            }
                            CommitRow(commit: commit, history: history)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

/// Separates local-only commits from the ones already on the remote.
private struct RemoteDivider: View {
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            Hairline()
            Text(name)
                .font(.mono(11))
                .fixedSize()
            Hairline()
        }
        .foregroundStyle(Palette.secondaryText)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct CommitRow: View {
    let commit: Commit
    let history: HistoryModel
    @Environment(\.glanceAccent) private var accent

    var body: some View {
        let isSelected = commit.sha == history.selectedSHA
        Button {
            history.select(commit)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(commit.title)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white : Palette.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Avatar(author: commit.author)
                    Text(commit.author.name)
                    if !commit.agents.isEmpty {
                        AgentChip(title: commit.agents.map(\.product).formatted(), inverted: isSelected)
                            .help("Co-authored by \(commit.agents.map(\.credit).formatted())")
                    }
                    if let tag = commit.tag {
                        TagChip(title: tag, inverted: isSelected)
                    }
                    Text("· \(commit.relativeTime)")
                    Spacer(minLength: 0)
                    if commit.isUnpushed {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 10))
                            .help("Not pushed")
                    }
                    Text(commit.shortSHA).font(.mono(11, weight: .medium))
                }
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Palette.secondaryText)
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(RowButtonStyle(fill: isSelected ? accent : nil))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
