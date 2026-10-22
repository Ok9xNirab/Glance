//
//  AppModel.swift
//  Glance
//

import AppKit
import Observation
import SwiftUI

enum ViewMode: Hashable {
    case changes, history, files
}

enum DiffLayout: Hashable {
    case unified, split
}

@Observable
final class AppModel {
    let repositoryName = SampleData.repositoryName
    let worktrees = SampleData.worktrees
    let branches = SampleData.branches

    var currentWorktreeID = SampleData.initialWorktreeID
    var mode = ViewMode.changes
    var diffLayout = DiffLayout.unified
    var isSidebarVisible = true
    var isSwitcherPresented = false

    let history = HistoryModel(commits: SampleData.commits)
    let files = FilesModel(tree: FileNode.build(SampleData.fileTree), contents: SampleData.fileContents)

    /// Which copy action most recently put text on the pasteboard, shown as feedback for a moment.
    private(set) var recentlyCopied: CopyTarget?
    private var copyResetTask: Task<Void, Never>?
    private let changesByWorktree: [Worktree.ID: ChangesModel]

    init() {
        changesByWorktree = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.id, ChangesModel(files: $0.changes)) })
    }

    var currentWorktree: Worktree {
        worktrees.first { $0.id == currentWorktreeID } ?? worktrees[0]
    }

    var changes: ChangesModel { changes(for: currentWorktree) }

    func changes(for worktree: Worktree) -> ChangesModel {
        changesByWorktree[worktree.id]!
    }

    func switchTo(_ worktree: Worktree) {
        currentWorktreeID = worktree.id
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) { isSidebarVisible.toggle() }
    }

    func toggleDiffLayout() {
        diffLayout = diffLayout == .unified ? .split : .unified
    }

    /// Opens the Changes view on `path` if it has uncommitted changes in the current worktree.
    func showDiff(forPath path: String) {
        guard let file = changes.files.first(where: { $0.id == path }) else { return }
        changes.select(file)
        mode = .changes
    }

    func goToFile() {
        mode = .files
        files.wantsSearchFocus = true
    }

    // MARK: Copying

    enum CopyTarget {
        case agentContext, path, sha
    }

    func copy(_ text: String, as target: CopyTarget) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        recentlyCopied = target
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.recentlyCopied = nil
        }
    }

    /// Copies whatever the current view is showing in a form that can be pasted straight into an agent.
    func copyForAgent() {
        switch mode {
        case .changes:
            if let file = changes.selectedFile { copy(file.diff.patch, as: .agentContext) }
        case .history:
            if let commit = history.selectedCommit { copy(commit.agentText, as: .agentContext) }
        case .files:
            if let path = files.activePath { copy(path, as: .path) }
        }
    }

    // MARK: Keyboard

    /// Handles the single-key shortcuts from the design. Returns `true` when the event was consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isSwitcherPresented, !(event.window?.firstResponder is NSText) else { return false }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if modifiers == .option, key == "s", mode != .files {
            toggleDiffLayout()
            return true
        }
        if modifiers == .command, key == "c", mode == .history, let commit = history.selectedCommit {
            copy(commit.sha, as: .sha)
            return true
        }
        guard modifiers.isEmpty else { return false }

        switch mode {
        case .changes:
            switch key {
            case "j": changes.selectNext()
            case "k": changes.selectPrevious()
            case "v": changes.toggleViewedForSelection()
            default: return false
            }
        case .history:
            switch event.keyCode {
            case 125: history.selectNext()
            case 126: history.selectPrevious()
            default: return false
            }
        case .files:
            return false
        }
        return true
    }
}
