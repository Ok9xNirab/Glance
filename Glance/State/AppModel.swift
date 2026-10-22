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
    private(set) var repositories: [Repository] = []
    var currentWorktreeID: Worktree.ID?
    var mode = ViewMode.changes
    var diffLayout = DiffLayout.unified
    var isSidebarVisible = true
    var isSwitcherPresented = false
    var isRepositoryPickerPresented = false
    /// An error to show, such as why a folder couldn't be added or why git refused a command.
    var alert: Alert?

    struct Alert {
        let title: String
        let message: String
    }

    let avatars = AvatarStore()
    let remoteDetails = RemoteDetailsStore()
    let history = HistoryModel(commits: SampleData.commits)
    let files = FilesModel(tree: FileNode.build(SampleData.fileTree), contents: SampleData.fileContents)

    /// Which copy action most recently put text on the pasteboard, shown as feedback for a moment.
    private(set) var recentlyCopied: CopyTarget?
    private var copyResetTask: Task<Void, Never>?
    @ObservationIgnored private var changesByWorktree: [Worktree.ID: ChangesModel] = [:]
    /// The worktree last open in each repository, so switching back returns to it.
    @ObservationIgnored private var lastWorktreeIDs: [Repository.ID: Worktree.ID] = [:]

    /// Repository paths, most recently opened first.
    private(set) var recentRepositoryPaths = UserDefaults.standard.stringArray(forKey: recentRepositoriesKey) ?? []
    private static let recentRepositoriesKey = "recentRepositoryPaths"

    init() {
        for url in RepositoryBookmarks.restore() {
            if let repository = try? GitRepositoryReader.read(url) { repositories.append(repository) }
        }
        currentWorktreeID = (recentRepositories.first ?? repositories.first)?.mainWorktree.id
    }

    var worktrees: [Worktree] { repositories.flatMap(\.worktrees) }

    var currentRepository: Repository? {
        repositories.first { $0.worktrees.contains { $0.id == currentWorktreeID } }
    }

    var repositoryName: String { currentRepository?.name ?? "" }
    var branches: [Branch] { currentRepository?.branches ?? [] }

    var currentWorktree: Worktree {
        worktrees.first { $0.id == currentWorktreeID } ?? worktrees.first ?? Worktree(name: "", branch: "", url: URL(filePath: "/"))
    }

    var changes: ChangesModel { changes(for: currentWorktree) }

    func changes(for worktree: Worktree) -> ChangesModel {
        if let changes = changesByWorktree[worktree.id] { return changes }
        let changes = ChangesModel(url: worktree.url)
        changes.onError = { [weak self] title, error in self?.alert = Alert(title: title, message: error.localizedDescription) }
        changesByWorktree[worktree.id] = changes
        return changes
    }

    func switchTo(_ worktree: Worktree) {
        currentWorktreeID = worktree.id
        guard let repository = currentRepository else { return }
        lastWorktreeIDs[repository.id] = worktree.id
        recentRepositoryPaths.removeAll { $0 == repository.url.path }
        recentRepositoryPaths.insert(repository.url.path, at: 0)
        UserDefaults.standard.set(recentRepositoryPaths, forKey: Self.recentRepositoriesKey)
    }

    /// Opens the worktree last used in `repository`, or its main worktree.
    func open(_ repository: Repository) {
        let worktree = repository.worktrees.first { $0.id == lastWorktreeIDs[repository.id] } ?? repository.mainWorktree
        switchTo(worktree)
    }

    var recentRepositories: [Repository] {
        recentRepositoryPaths.compactMap { path in repositories.first { $0.url.path == path } }
    }

    // MARK: Repositories

    /// Asks for folders that contain Git repositories and adds them to the sidebar.
    func addRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose a folder that contains a Git repository."
        guard panel.runModal() == .OK else { return }

        var errors: [String] = []
        for url in panel.urls {
            if let existing = repositories.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                open(existing)
                continue
            }
            do {
                let repository = try GitRepositoryReader.read(url)
                repositories.append(repository)
                switchTo(repository.mainWorktree)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        RepositoryBookmarks.save(repositories.map(\.url))
        alert = errors.isEmpty ? nil : Alert(title: "Couldn’t Add Repository", message: errors.joined(separator: "\n\n"))
        if errors.isEmpty { isRepositoryPickerPresented = false }
    }

    func removeRepository(_ repository: Repository) {
        repositories.removeAll { $0.id == repository.id }
        for worktree in repository.worktrees { changesByWorktree[worktree.id] = nil }
        RepositoryBookmarks.save(repositories.map(\.url))
        repository.url.stopAccessingSecurityScopedResource()
        recentRepositoryPaths.removeAll { $0 == repository.url.path }
        UserDefaults.standard.set(recentRepositoryPaths, forKey: Self.recentRepositoriesKey)
        if !worktrees.contains(where: { $0.id == currentWorktreeID }) {
            currentWorktreeID = (recentRepositories.first ?? repositories.first)?.mainWorktree.id
        }
    }

    /// Re-reads every repository, so worktrees and branches made outside Glance show up, and stops watching
    /// worktrees that are gone.
    func reloadRepositories() {
        repositories = repositories.map { (try? GitRepositoryReader.read($0.url)) ?? $0 }
        let ids = Set(worktrees.map(\.id))
        changesByWorktree = changesByWorktree.filter { ids.contains($0.key) }
        if !worktrees.contains(where: { $0.id == currentWorktreeID }) {
            currentWorktreeID = worktrees.first?.id
        }
    }

    // MARK: Worktrees and branches

    /// Turns what was typed in the switcher into a branch name git accepts: "rate limit" becomes "rate-limit".
    private func branchName(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }

    /// Adds a worktree at `<repository>/.worktrees/<name>`, checking out `branch` or creating it from the current
    /// worktree's `HEAD` when it doesn't exist yet.
    func createWorktree(branch text: String) {
        guard let repository = currentRepository else { return }
        let branch = branchName(text)
        let folder = repository.url.appending(path: ".worktrees/\(branch.replacingOccurrences(of: "/", with: "-"))")
        let arguments = repository.branches.contains { $0.name == branch }
            ? ["worktree", "add", folder.path, branch]
            : ["worktree", "add", "-b", branch, folder.path]
        runGit(arguments, in: currentWorktree.url, failure: "Couldn’t Create Worktree") {
            try Self.excludeWorktreesFolder(in: repository)
            return folder.standardizedFileURL.path
        }
    }

    /// Creates `branch` from the current worktree's `HEAD` and switches that worktree to it.
    func createBranch(_ text: String) {
        runGit(["switch", "-c", branchName(text)], in: currentWorktree.url, failure: "Couldn’t Create Branch")
    }

    func checkOut(_ branch: Branch) {
        runGit(["switch", branch.name], in: currentWorktree.url, failure: "Couldn’t Check Out \(branch.name)")
    }

    /// Runs git, then re-reads the repositories and opens the worktree whose path `then` returns, if any.
    private func runGit(_ arguments: [String], in directory: URL, failure: String, then: @escaping () throws -> String? = { nil }) {
        Task {
            do {
                try await Git.run(arguments, in: directory)
                let path = try then()
                reloadRepositories()
                if let path, let worktree = worktrees.first(where: { $0.id == path }) { switchTo(worktree) }
            } catch {
                reloadRepositories()
                alert = Alert(title: failure, message: error.localizedDescription)
            }
        }
    }

    /// Keeps `.worktrees/` out of `git status` by listing it in `.git/info/exclude`, which isn't committed.
    private static func excludeWorktreesFolder(in repository: Repository) throws {
        let exclude = repository.url.appending(path: ".git/info/exclude")
        let contents = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
        guard !contents.split(separator: "\n").contains(where: { $0 == "/.worktrees/" || $0 == ".worktrees/" || $0 == ".worktrees" }) else { return }
        try FileManager.default.createDirectory(at: exclude.deletingLastPathComponent(), withIntermediateDirectories: true)
        let separator = contents.isEmpty || contents.hasSuffix("\n") ? "" : "\n"
        try (contents + separator + "/.worktrees/\n").write(to: exclude, atomically: true, encoding: .utf8)
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
        guard !isSwitcherPresented, !isRepositoryPickerPresented, !(event.window?.firstResponder is NSText) else { return false }

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
