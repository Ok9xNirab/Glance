//
//  SidebarView.swift
//  Glance
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TopBar(showsSeparator: false) {
                Spacer()
                IconButton("sidebar.left", help: "Hide Sidebar", action: model.toggleSidebar)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeading(title: "Worktrees")
                    VStack(spacing: 1) {
                        ForEach(model.worktrees) { worktree in
                            WorktreeRow(worktree: worktree)
                        }
                    }
                    .padding(.horizontal, 10)

                    SectionHeading(title: "Branches")
                        .padding(.top, 4)
                    VStack(spacing: 1) {
                        ForEach(model.branches.filter(\.isRecent)) { branch in
                            BranchRow(branch: branch)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.bottom, 10)
            }

            HStack(spacing: 2) {
                IconButton("plus", help: "New Worktree or Branch") { model.isSwitcherPresented = true }
                Spacer()
                Button {
                    model.isSwitcherPresented = true
                } label: {
                    HStack(spacing: 6) {
                        KeyCap("⌘K")
                        Text("Switch")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(alignment: .top) { Hairline() }
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Palette.sidebar)
        .overlay(alignment: .trailing) { Hairline(axis: .vertical) }
    }
}

private struct SectionHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct WorktreeRow: View {
    let worktree: Worktree
    @Environment(AppModel.self) private var model
    @Environment(\.glanceAccent) private var accent

    var body: some View {
        let isCurrent = worktree.id == model.currentWorktreeID
        Button {
            model.switchTo(worktree)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(worktree.name)
                    Text(worktree.branch)
                        .font(.mono(11))
                        .foregroundStyle(Palette.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if worktree.isAgentActive {
                    AgentDot().help("Agent is writing files")
                }
                if !worktree.changes.isEmpty {
                    CountBadge(count: worktree.changes.count)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
        }
        .buttonStyle(RowButtonStyle(fill: isCurrent ? Palette.selection : nil))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private struct BranchRow: View {
    let branch: Branch

    var body: some View {
        Button {} label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                Text(branch.name)
                    .font(.mono(12))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: 28)
        }
        .buttonStyle(RowButtonStyle())
    }
}
