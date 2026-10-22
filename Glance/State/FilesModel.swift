//
//  FilesModel.swift
//  Glance
//

import Foundation
import Observation

/// One worktree's files, listed with git and refreshed whenever its files change. Statuses and changed lines come
/// from the worktree's `ChangesModel`, so they always match the Changes view.
@Observable
final class FilesModel {
    struct Tab: Identifiable, Equatable {
        let path: String
        /// A preview tab is replaced by the next file opened with a single click.
        var isPreview = false

        var id: String { path }
    }

    struct TreeRow: Identifiable {
        let node: FileNode
        let depth: Int
        let status: FileStatus?
        /// For a folder, whether a file inside it has changes.
        let containsChanges: Bool
        /// Search results are flat, so they show the folder next to the name.
        var showsParent = false

        var id: String { node.path }
    }

    let url: URL
    private let changes: ChangesModel
    /// The files git lists, tracked or untracked but not ignored.
    private var listedPaths: Set<String> = []
    /// Bumped whenever `listedPaths` changes, so the tree is only rebuilt then.
    private var listVersion = 0
    /// `false` until git has been read once, so an empty tree isn't announced before it's known.
    private(set) var isLoaded = false
    /// The open tabs' contents, read when they're opened and again when files change.
    private(set) var loaded: [String: LoadedFile] = [:]

    var expandedFolders: Set<String> = []
    var tabs: [Tab] = []
    var activePath: String?
    /// The lines the editor's selection touches; a bare caret selects just its own line.
    var selectedLines = 1...1
    var currentColumn = 1
    var query = ""
    var changedOnly = false
    /// Set by ⌘P; the file list focuses its search field and clears this.
    var wantsSearchFocus = false

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var loadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var cachedTree: (version: Int, extraPaths: Set<String>, tree: [FileNode], files: [FileNode])?

    init(url: URL, changes: ChangesModel) {
        self.url = url
        self.changes = changes
        watcher = FileWatcher(url) { [weak self] in self?.refresh() }
        refresh()
    }

    // MARK: Reading

    /// Lists the files again and re-reads the open tabs.
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [url] in
            let paths = (try? await WorktreeFileReader.list(url)) ?? []
            guard !Task.isCancelled else { return }
            if paths != listedPaths {
                listedPaths = paths
                listVersion += 1
            }
            isLoaded = true
            for tab in tabs { load(tab.path) }
        }
    }

    private func load(_ path: String) {
        loadTasks[path]?.cancel()
        let deleted = status(of: path) == .deleted
        loadTasks[path] = Task { [url] in
            let file = await WorktreeFileReader.read(path, in: url, deleted: deleted)
            guard !Task.isCancelled, tabs.contains(where: { $0.path == path }) else { return }
            if loaded[path] != file { loaded[path] = file }
            loadTasks[path] = nil
        }
    }

    // MARK: Tree

    /// Files git lists, plus deleted files, which it doesn't once an agent has removed them from the index.
    private var treeAndFiles: (tree: [FileNode], files: [FileNode]) {
        let extraPaths = Set(changes.files.map(\.id)).subtracting(listedPaths)
        if let cachedTree, cachedTree.version == listVersion, cachedTree.extraPaths == extraPaths {
            return (cachedTree.tree, cachedTree.files)
        }
        let tree = FileNode.build(listedPaths.union(extraPaths))
        let files = FileNode.flatten(tree)
        cachedTree = (listVersion, extraPaths, tree, files)
        return (tree, files)
    }

    var tree: [FileNode] { treeAndFiles.tree }
    var allFiles: [FileNode] { treeAndFiles.files }

    private var statuses: [String: FileStatus] {
        Dictionary(changes.files.map { ($0.id, $0.diff.status) }, uniquingKeysWith: { first, _ in first })
    }

    /// Every folder that has a changed file somewhere inside it.
    private func changedFolders(_ statuses: [String: FileStatus]) -> Set<String> {
        var folders: Set<String> = []
        for path in statuses.keys {
            var folder = path.pathDirectory.dropLast()
            while !folder.isEmpty, folders.insert(String(folder)).inserted {
                folder = String(folder).pathDirectory.dropLast()
            }
        }
        return folders
    }

    var rows: [TreeRow] {
        let statuses = statuses
        if !query.isEmpty {
            return allFiles
                .filter { $0.path.localizedCaseInsensitiveContains(query) && (!changedOnly || statuses[$0.path] != nil) }
                .map { TreeRow(node: $0, depth: 0, status: statuses[$0.path], containsChanges: false, showsParent: $0.path.contains("/")) }
        }

        let changedFolders = changedFolders(statuses)
        var rows: [TreeRow] = []
        func walk(_ nodes: [FileNode], depth: Int) {
            for node in nodes {
                let status = statuses[node.path]
                let containsChanges = node.isFolder ? changedFolders.contains(node.path) : status != nil
                if changedOnly && !containsChanges { continue }
                rows.append(TreeRow(node: node, depth: depth, status: status, containsChanges: containsChanges))
                if let children = node.children, isExpanded(node) {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(tree, depth: 0)
        return rows
    }

    var changedCount: Int { changes.files.count }

    func status(of path: String) -> FileStatus? {
        changes.files.first { $0.id == path }?.diff.status
    }

    /// "Changed only" shows every folder on the way to a change, so it forces folders open.
    func isExpanded(_ node: FileNode) -> Bool {
        node.isFolder && (expandedFolders.contains(node.path) || changedOnly)
    }

    func toggleFolder(_ node: FileNode) {
        if expandedFolders.contains(node.path) {
            expandedFolders.remove(node.path)
        } else {
            expandedFolders.insert(node.path)
        }
    }

    func collapseAll() {
        expandedFolders.removeAll()
    }

    // MARK: Editor

    /// The active file with its uncommitted changes marked, or `nil` while it's read or when it can't be shown.
    var activeContent: FileContent? {
        guard let activePath, case var .text(content) = loaded[activePath] else { return nil }
        content.marks = marks(for: activePath)
        return content
    }

    /// Why the active file isn't shown.
    var activeMessage: String? {
        guard let activePath else { return "No file open. Pick one from the tree or press ⌘P." }
        if case let .unavailable(message) = loaded[activePath] { return message }
        return nil
    }

    /// Added lines from the file's diff against `HEAD`. Additions that replace deletions count as modified.
    private func marks(for path: String) -> [Int: FileContent.Mark] {
        guard let file = changes.files.first(where: { $0.id == path }), file.diff.status != .deleted else { return [:] }
        var marks: [Int: FileContent.Mark] = [:]
        for hunk in file.diff.hunks ?? [] {
            var replaced = 0
            for line in hunk.lines {
                switch line.kind {
                case .deletion:
                    replaced += 1
                case .addition:
                    if let number = line.newNumber { marks[number] = replaced > 0 ? .modified : .added }
                    replaced = max(replaced - 1, 0)
                case .context:
                    replaced = 0
                }
            }
        }
        return marks
    }

    var currentLine: Int { selectedLines.lowerBound }

    /// The active file with its selected lines, e.g. `src/app.ts:12-18`, for pasting into an agent prompt.
    var activeReference: String? {
        guard let activePath else { return nil }
        let lines = selectedLines.count == 1
            ? "\(selectedLines.lowerBound)"
            : "\(selectedLines.lowerBound)-\(selectedLines.upperBound)"
        return "\(activePath):\(lines)"
    }

    // MARK: Tabs

    /// Opens `path` in the preview tab, or in a tab of its own when `pinned`, and reveals it in the tree.
    func open(_ path: String, pinned: Bool) {
        if let index = tabs.firstIndex(where: { $0.path == path }) {
            if pinned { tabs[index].isPreview = false }
        } else {
            let tab = Tab(path: path, isPreview: !pinned)
            if let previewIndex = tabs.firstIndex(where: \.isPreview) {
                forget(tabs[previewIndex].path)
                tabs[previewIndex] = tab
            } else {
                tabs.append(tab)
            }
            load(path)
        }
        var folder = path.pathDirectory.dropLast()
        while !folder.isEmpty {
            expandedFolders.insert(String(folder))
            folder = String(folder).pathDirectory.dropLast()
        }
        activePath = path
        selectedLines = 1...1
        currentColumn = 1
    }

    func activate(_ tab: Tab) {
        activePath = tab.path
        selectedLines = 1...1
        currentColumn = 1
    }

    func close(_ tab: Tab) {
        tabs.removeAll { $0.path == tab.path }
        forget(tab.path)
        if activePath == tab.path {
            activePath = tabs.last?.path
        }
    }

    private func forget(_ path: String) {
        loadTasks.removeValue(forKey: path)?.cancel()
        loaded[path] = nil
    }
}
