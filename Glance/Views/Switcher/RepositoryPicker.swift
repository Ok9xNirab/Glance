//
//  RepositoryPicker.swift
//  Glance
//

import SwiftUI

/// The ⌘T palette for switching repositories, grouped by the owner of each repository's remote.
struct RepositoryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.glanceAccent) private var accent
    @State private var query = ""
    @State private var focusedIndex = 0
    @State private var collapsedGroups: Set<String> = []
    @FocusState private var isSearchFocused: Bool

    /// Recent repositories are listed separately once there are too many to see at a glance.
    private static let recentThreshold = 4
    private static let recentLimit = 3

    private struct OwnerGroup: Identifiable {
        enum Kind { case recent, owner, local }

        let id: String
        let title: String
        let kind: Kind
        let repositories: [Repository]
    }

    private struct Row: Identifiable {
        let group: OwnerGroup
        let repository: Repository

        var id: String { "\(group.id)/\(repository.url.path)" }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            panel
                .padding(.top, 80)
        }
        .onAppear { isSearchFocused = true }
    }

    private var panel: some View {
        let groups = groups
        let rows = groups.filter(isOpen).flatMap { group in group.repositories.map { Row(group: group, repository: $0) } }
        return VStack(spacing: 0) {
            header(rows)
            results(groups, rows: rows)
            HStack(spacing: 12) {
                ShortcutHint(keys: ["↑", "↓"], label: "move")
                ShortcutHint(keys: ["↵"], label: "open")
                Spacer()
                KeyCap("⌘T")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .top) { Hairline() }
        }
        .frame(width: 420)
        .background(Palette.switcherPanel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 18)
        .shadow(color: .black.opacity(0.08), radius: 5, y: 3)
        .onExitCommand(perform: dismiss)
        .accessibilityAddTraits(.isModal)
    }

    private func header(_ rows: [Row]) -> some View {
        HStack(spacing: 8) {
            SearchField("Filter repositories", text: $query, isFocused: $isSearchFocused)
                .onChange(of: query) { focusedIndex = 0 }
                .onSubmit { if rows.indices.contains(focusedIndex) { open(rows[focusedIndex].repository) } }
                .onKeyPress(.downArrow) {
                    focusedIndex = min(focusedIndex + 1, rows.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    focusedIndex = max(focusedIndex - 1, 0)
                    return .handled
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
            Menu {
                Button("Add Local Folder…", action: model.addRepository)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text("Add")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(BezelButtonStyle(height: 26))
            .fixedSize()
            .help("Add a local folder that contains a Git repository")
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12))
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func results(_ groups: [OwnerGroup], rows: [Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty {
                        Text(query.isEmpty ? "No repositories yet." : "No repositories match “\(query)”")
                            .foregroundStyle(Palette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                    ForEach(groups) { group in
                        groupHeading(group)
                        if isOpen(group) {
                            ForEach(group.repositories, id: \.url) { repository in
                                let row = Row(group: group, repository: repository)
                                let index = rows.firstIndex { $0.id == row.id } ?? 0
                                repositoryRow(row, isFocused: index == focusedIndex)
                                    .id(row.id)
                                    .onHover { if $0 { focusedIndex = index } }
                            }
                        }
                    }
                }
                .padding(EdgeInsets(top: 2, leading: 8, bottom: 10, trailing: 8))
            }
            .frame(maxHeight: 520)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: focusedIndex) {
                if rows.indices.contains(focusedIndex) { proxy.scrollTo(rows[focusedIndex].id) }
            }
        }
    }

    // MARK: Rows

    private func groupHeading(_ group: OwnerGroup) -> some View {
        Button {
            if collapsedGroups.contains(group.id) {
                collapsedGroups.remove(group.id)
            } else {
                collapsedGroups.insert(group.id)
            }
            focusedIndex = 0
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isOpen(group) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 12)
                switch group.kind {
                case .owner:
                    OwnerAvatar(repository: group.repositories[0])
                case .recent:
                    groupIcon("clock")
                case .local:
                    groupIcon("tray")
                }
                Text(group.title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(group.repositories.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
        .buttonStyle(RowButtonStyle())
        .padding(.top, 6)
        .accessibilityValue(isOpen(group) ? "Expanded" : "Collapsed")
    }

    private func groupIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12))
            .foregroundStyle(Palette.secondaryText)
            .frame(width: 18, height: 18)
    }

    private func repositoryRow(_ row: Row, isFocused: Bool) -> some View {
        let repository = row.repository
        let isCurrent = repository.id == model.currentRepository?.id
        let changeCount = repository.worktrees.reduce(0) { $0 + model.changes(for: $1).files.count }
        let remote = model.remoteDetails.details(for: repository)
        let detail = row.group.kind == .recent ? repository.owner ?? "Local only"
            : repository.owner == nil ? "Local only · no remote"
            : remote?.forkParent.map { "Fork of \($0)" }
        let secondary = isFocused ? Color.white.opacity(0.88) : Palette.secondaryText

        return Button {
            open(repository)
        } label: {
            HStack(spacing: 9) {
                Group {
                    if repository.owner == nil {
                        Image(systemName: "folder")
                    } else if remote?.forkParent != nil {
                        ForkIcon().accessibilityLabel("Fork")
                    } else if remote?.isPrivate == true {
                        Image(systemName: "lock").accessibilityLabel("Private")
                    } else {
                        Image(systemName: "book.closed")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(secondary)
                .frame(width: 15)
                VStack(alignment: .leading, spacing: 0) {
                    Text(repository.name)
                        .fontWeight(.medium)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(secondary)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    if repository.worktrees.count > 1 {
                        chip("\(repository.worktrees.count) worktrees", isFocused: isFocused)
                            .help("Worktrees")
                    }
                    if repository.worktrees.contains(where: \.isAgentActive) {
                        AgentDot(color: isFocused ? .white : Palette.agentDot)
                            .help("An agent is writing files")
                    }
                    if changeCount > 0 {
                        chip("\(changeCount)", isFocused: isFocused)
                    }
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(secondary)
                            .accessibilityLabel("Current repository")
                    }
                }
            }
            .foregroundStyle(isFocused ? .white : Palette.text)
            .padding(EdgeInsets(top: 4, leading: 34, bottom: 4, trailing: 8))
            .frame(minHeight: 32)
        }
        .buttonStyle(RowButtonStyle(fill: isFocused ? accent : nil))
        .help(repository.url.path)
        .task(id: repository.url) { await model.remoteDetails.load(repository) }
        .contextMenu {
            Button("Remove “\(repository.name)” from Glance") { model.removeRepository(repository) }
        }
    }

    private func chip(_ text: String, isFocused: Bool) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(isFocused ? .white : Palette.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(Capsule().fill(isFocused ? Color.white.opacity(0.22) : Palette.selection))
    }

    // MARK: Grouping

    private var groups: [OwnerGroup] {
        let matching = model.repositories.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.owner?.localizedCaseInsensitiveContains(query) == true
        }
        var groups: [OwnerGroup] = []
        if query.isEmpty, model.repositories.count >= Self.recentThreshold {
            let recent = Array(model.recentRepositories.prefix(Self.recentLimit))
            if !recent.isEmpty { groups.append(OwnerGroup(id: "recent", title: "Recent", kind: .recent, repositories: recent)) }
        }

        let byOwner = Dictionary(grouping: matching.filter { $0.owner != nil }, by: { $0.owner! })
        for owner in byOwner.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            groups.append(OwnerGroup(id: "owner:\(owner)", title: owner, kind: .owner, repositories: sortedByName(byOwner[owner]!)))
        }

        let local = matching.filter { $0.owner == nil }
        if !local.isEmpty {
            groups.append(OwnerGroup(id: "local", title: "Other", kind: .local, repositories: sortedByName(local)))
        }
        return groups
    }

    private func sortedByName(_ repositories: [Repository]) -> [Repository] {
        repositories.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Filtering opens every group so matches aren't hidden.
    private func isOpen(_ group: OwnerGroup) -> Bool {
        !query.isEmpty || !collapsedGroups.contains(group.id)
    }

    // MARK: Actions

    private func open(_ repository: Repository) {
        model.open(repository)
        dismiss()
    }

    private func dismiss() {
        model.isRepositoryPickerPresented = false
    }
}
