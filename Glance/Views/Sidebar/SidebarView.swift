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

            if model.repositories.isEmpty {
                VStack(spacing: 10) {
                    Text("Add a folder that contains a Git repository.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Add Repository…", action: model.addRepository)
                        .buttonStyle(BezelButtonStyle())
                }
                .padding(20)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let repository = model.currentRepository {
                            RepositoryButton(repository: repository)
                                .padding(.horizontal, 10)
                                .padding(.top, 2)

                            SectionHeading(title: "Worktrees")
                            VStack(spacing: 1) {
                                ForEach(repository.worktrees) { worktree in
                                    WorktreeRow(worktree: worktree)
                                }
                            }
                            .padding(.horizontal, 10)

                            let recentBranches = repository.branches.filter(\.isRecent)
                            if !recentBranches.isEmpty {
                                SectionHeading(title: "Branches")
                                    .padding(.top, 4)
                                VStack(spacing: 1) {
                                    ForEach(recentBranches) { branch in
                                        BranchRow(branch: branch)
                                    }
                                }
                                .padding(.horizontal, 10)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }

            HStack(spacing: 2) {
                IconButton("folder.badge.plus", help: "New Worktree or Branch") { model.isSwitcherPresented = true }
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

/// The current repository, which opens the repository picker.
private struct RepositoryButton: View {
    let repository: Repository
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.isRepositoryPickerPresented = true
        } label: {
            HStack(spacing: 9) {
                OwnerAvatar(repository: repository, size: 24, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(repository.owner ?? "Local only")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                    Text(repository.name)
                        .fontWeight(.semibold)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .buttonStyle(RowButtonStyle(cornerRadius: 8, fill: Palette.selection))
        .help("Switch Repository (⌘T)")
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
