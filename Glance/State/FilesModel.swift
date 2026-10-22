//
//  FilesModel.swift
//  Glance
//

import Foundation
import Observation

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
        /// Search results are flat, so they show the folder next to the name.
        var showsParent = false

        var id: String { node.path }
    }

    let tree: [FileNode]
    let allFiles: [FileNode]
    private let contents: [String: FileContent]

    var expandedFolders: Set<String> = ["src", "src/middleware", "src/routes", "test"]
    var tabs: [Tab] = [
        Tab(path: "src/server.ts"),
        Tab(path: "src/routes/checkout.ts"),
        Tab(path: "src/middleware/rateLimit.ts", isPreview: true),
    ]
    var activePath: String? = "src/middleware/rateLimit.ts"
    var currentLine = 19
    var query = ""
    var changedOnly = false
    /// Set by ⌘P; the file list focuses its search field and clears this.
    var wantsSearchFocus = false

    init(tree: [FileNode], contents: [String: FileContent]) {
        self.tree = tree
        self.contents = contents
        allFiles = FileNode.flatten(tree)
    }

    var rows: [TreeRow] {
        if !query.isEmpty {
            return allFiles
                .filter { $0.path.localizedCaseInsensitiveContains(query) && (!changedOnly || $0.status != nil) }
                .map { TreeRow(node: $0, depth: 0, showsParent: $0.path.contains("/")) }
        }

        var rows: [TreeRow] = []
        func walk(_ nodes: [FileNode], depth: Int) {
            for node in nodes {
                if changedOnly && !node.containsChanges { continue }
                rows.append(TreeRow(node: node, depth: depth))
                if let children = node.children, isExpanded(node) {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(tree, depth: 0)
        return rows
    }

    var changedCount: Int { allFiles.count { $0.status != nil } }

    var activeContent: FileContent? {
        activePath.flatMap { contents[$0] }
    }

    func status(of path: String) -> FileStatus? {
        allFiles.first { $0.path == path }?.status
    }

    // MARK: Tree

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

    // MARK: Tabs

    /// Opens `path` in the preview tab, or in a tab of its own when `pinned`.
    func open(_ path: String, pinned: Bool) {
        if let index = tabs.firstIndex(where: { $0.path == path }) {
            if pinned { tabs[index].isPreview = false }
        } else {
            let tab = Tab(path: path, isPreview: !pinned)
            if let previewIndex = tabs.firstIndex(where: \.isPreview) {
                tabs[previewIndex] = tab
            } else {
                tabs.append(tab)
            }
        }
        activePath = path
        currentLine = 1
    }

    func activate(_ tab: Tab) {
        activePath = tab.path
        currentLine = 1
    }

    func close(_ tab: Tab) {
        tabs.removeAll { $0.path == tab.path }
        if activePath == tab.path {
            activePath = tabs.last?.path
        }
    }
}
