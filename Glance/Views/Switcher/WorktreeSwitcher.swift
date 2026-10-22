//
//  WorktreeSwitcher.swift
//  Glance
//

import SwiftUI

/// The ⌘K palette for jumping between worktrees and branches.
struct WorktreeSwitcher: View {
    @Environment(AppModel.self) private var model
    @Environment(\.glanceAccent) private var accent
    @State private var query = ""
    @State private var focusedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private enum Entry: Identifiable {
        /// `editedFile` is set when the worktree matched only because the agent is editing that file.
        case worktree(Worktree, editedFile: String?)
        case branch(Branch)
        case newWorktree
        case newBranch

        var id: String {
            switch self {
            case let .worktree(worktree, _): "worktree:\(worktree.id)"
            case let .branch(branch): "branch:\(branch.id)"
            case .newWorktree: "new-worktree"
            case .newBranch: "new-branch"
            }
        }
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
        let entries = worktreeEntries + branchEntries + actionEntries
        return VStack(spacing: 0) {
            searchRow(entries)
            results(entries)
            HStack(spacing: 14) {
                ShortcutHint(keys: ["↑", "↓"], label: "move")
                ShortcutHint(keys: ["↵"], label: "open")
                ShortcutHint(keys: ["⌘↵"], label: "open in new window")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Hairline() }
        }
        .frame(width: 560)
        .background(Palette.switcherPanel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 30, y: 24)
        .shadow(color: .black.opacity(0.1), radius: 7, y: 4)
        .onExitCommand(perform: dismiss)
        .accessibilityAddTraits(.isModal)
    }

    private func searchRow(_ entries: [Entry]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Palette.secondaryText)
            TextField("Switch to a worktree or branch", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isSearchFocused)
                .onChange(of: query) { focusedIndex = 0 }
                .onSubmit { if entries.indices.contains(focusedIndex) { activate(entries[focusedIndex]) } }
                .onKeyPress(.downArrow) {
                    focusedIndex = min(focusedIndex + 1, entries.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    focusedIndex = max(focusedIndex - 1, 0)
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard !query.isEmpty else { return .ignored }
                    if press.modifiers == .option {
                        activate(.newWorktree)
                    } else if press.modifiers == .shift {
                        activate(.newBranch)
                    } else {
                        return .ignored
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
            KeyCap("esc").foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func results(_ entries: [Entry]) -> some View {
        let worktreeCount = worktreeEntries.count
        let branchCount = branchEntries.count
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        Text("No worktrees or branches match.")
                            .foregroundStyle(Palette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index == 0, worktreeCount > 0 {
                            GroupHeading(title: "Worktrees")
                        }
                        if index == worktreeCount, branchCount > 0 {
                            GroupHeading(title: "Branches without a worktree")
                                .padding(.top, worktreeCount > 0 ? 2 : 0)
                        }
                        if index == worktreeCount + branchCount {
                            Hairline().padding(EdgeInsets(top: 8, leading: 8, bottom: 4, trailing: 8))
                        }
                        row(for: entry, isFocused: index == focusedIndex)
                            .id(entry.id)
                            .onHover { if $0 { focusedIndex = index } }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: focusedIndex) {
                if entries.indices.contains(focusedIndex) { proxy.scrollTo(entries[focusedIndex].id) }
            }
        }
    }

    // MARK: Rows

    @ViewBuilder private func row(for entry: Entry, isFocused: Bool) -> some View {
        switch entry {
        case let .worktree(worktree, editedFile):
            worktreeRow(worktree, editedFile: editedFile, isFocused: isFocused)
        case let .branch(branch):
            branchRow(branch, isFocused: isFocused)
        case .newWorktree:
            actionRow("New worktree from “\(query)”", systemImage: "plus", shortcut: "⌥↵", isFocused: isFocused, entry: entry)
        case .newBranch:
            actionRow("New branch “\(query)” in this worktree", systemImage: "arrow.triangle.branch", shortcut: "⇧↵", isFocused: isFocused, entry: entry)
        }
    }

    private func worktreeRow(_ worktree: Worktree, editedFile: String?, isFocused: Bool) -> some View {
        let isCurrent = worktree.id == model.currentWorktreeID
        var detail = highlighted(worktree.branch)
        detail += AttributedString(isCurrent ? " · current" : " · \(worktree.path)")
        if let editedFile {
            detail += AttributedString(" · edits ")
            detail += highlighted(editedFile)
        }

        return Button {
            activate(.worktree(worktree, editedFile: editedFile))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 15))
                    .foregroundStyle(isFocused ? .white : accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(highlighted(worktree.name))
                    Text(detail)
                        .font(.mono(11))
                        .foregroundStyle(isFocused ? .white.opacity(0.85) : Palette.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                let changeCount = model.changes(for: worktree).files.count
                if changeCount > 0 {
                    HStack(spacing: 6) {
                        if worktree.isAgentActive {
                            AgentDot(color: isFocused ? .white : Palette.agentDot)
                        }
                        Text("\(changeCount) \(changeCount == 1 ? "change" : "changes")")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(isFocused ? .white.opacity(0.85) : Palette.secondaryText)
                }
                if isFocused {
                    KeyCap("↵", inverted: true)
                } else if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .foregroundStyle(isFocused ? .white : Palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 40)
        }
        .buttonStyle(RowButtonStyle(cornerRadius: 7, fill: isFocused ? accent : nil))
    }

    private func branchRow(_ branch: Branch, isFocused: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondaryText)
            VStack(alignment: .leading, spacing: 1) {
                Text(highlighted(branch.name))
                    .font(.mono(12.5))
                Text([branch.lastUpdated.map { "Updated \($0.formatted(.relative(presentation: .named)))" }, branch.remote ?? "local only"]
                    .compactMap(\.self)
                    .joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Check Out") {
                model.checkOut(branch)
                dismiss()
            }
            Button("New Worktree") {
                model.createWorktree(branch: branch.name)
                dismiss()
            }
        }
        .buttonStyle(BezelButtonStyle(height: 22))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 40)
        .background(RoundedRectangle(cornerRadius: 7).fill(isFocused ? Palette.hover : .clear))
    }

    private func actionRow(_ title: String, systemImage: String, shortcut: String, isFocused: Bool, entry: Entry) -> some View {
        Button {
            activate(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(isFocused ? .white : Palette.secondaryText)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                KeyCap(shortcut, inverted: isFocused)
                    .foregroundStyle(isFocused ? .white : Palette.secondaryText)
            }
            .foregroundStyle(isFocused ? .white : Palette.text)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
        }
        .buttonStyle(RowButtonStyle(cornerRadius: 7, fill: isFocused ? accent : nil))
    }

    // MARK: Matching

    /// The current repository's worktrees; other repositories are reached through the ⌘T picker.
    private var worktrees: [Worktree] { model.currentRepository?.worktrees ?? [] }

    private var worktreeEntries: [Entry] {
        guard !query.isEmpty else { return worktrees.map { .worktree($0, editedFile: nil) } }
        let direct = worktrees.filter { matches($0.name) || matches($0.branch) }
        let byFile: [Entry] = worktrees.compactMap { worktree in
            guard !direct.contains(where: { $0.id == worktree.id }),
                  let file = model.changes(for: worktree).files.first(where: { matches($0.diff.name) })
            else { return nil }
            return .worktree(worktree, editedFile: file.diff.name)
        }
        return direct.map { .worktree($0, editedFile: nil) } + byFile
    }

    private var branchEntries: [Entry] {
        let checkedOut = Set(worktrees.map(\.branch))
        return model.branches.filter { !checkedOut.contains($0.name) && (query.isEmpty || matches($0.name)) }.map(Entry.branch)
    }

    private var actionEntries: [Entry] {
        query.isEmpty ? [] : [.newWorktree, .newBranch]
    }

    private func matches(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains(query)
    }

    /// Bolds and underlines the first occurrence of the query.
    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty, let range = result.range(of: query, options: .caseInsensitive) else { return result }
        result[range].inlinePresentationIntent = .stronglyEmphasized
        result[range].underlineStyle = .single
        return result
    }

    // MARK: Actions

    private func activate(_ entry: Entry) {
        switch entry {
        case let .worktree(worktree, _): model.switchTo(worktree)
        case let .branch(branch): model.checkOut(branch)
        case .newWorktree: model.createWorktree(branch: query)
        case .newBranch: model.createBranch(query)
        }
        dismiss()
    }

    private func dismiss() {
        model.isSwitcherPresented = false
    }
}

private struct GroupHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
