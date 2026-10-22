//
//  FileTree.swift
//  Glance
//

import Foundation

/// A compact way to write a project tree in the sample data.
indirect enum TreeEntry {
    case folder(String, [TreeEntry])
    case file(String, FileStatus? = nil)
}

struct FileNode: Identifiable {
    let name: String
    let path: String
    let status: FileStatus?
    /// `nil` for files.
    let children: [FileNode]?
    let containsChanges: Bool

    var id: String { path }
    var isFolder: Bool { children != nil }
    var parentPath: String { String(path.pathDirectory.dropLast()) }

    static func build(_ entries: [TreeEntry], parent: String = "") -> [FileNode] {
        entries.map { entry in
            switch entry {
            case let .folder(name, entries):
                let path = parent.isEmpty ? name : "\(parent)/\(name)"
                let children = build(entries, parent: path)
                let containsChanges = children.contains { $0.isFolder ? $0.containsChanges : $0.status != nil }
                return FileNode(name: name, path: path, status: nil, children: children, containsChanges: containsChanges)
            case let .file(name, status):
                let path = parent.isEmpty ? name : "\(parent)/\(name)"
                return FileNode(name: name, path: path, status: status, children: nil, containsChanges: status != nil)
            }
        }
    }

    /// Every file under `nodes`, depth first.
    static func flatten(_ nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { node in node.children.map { flatten($0) } ?? [node] }
    }
}

struct FileContent {
    enum Mark {
        case added, modified
    }

    let lines: [String]
    /// Uncommitted-change markers keyed by 1-based line number.
    let marks: [Int: Mark]

    init(marks: [Int: Mark] = [:], _ lines: [String]) {
        self.lines = lines
        self.marks = marks
    }

    static func added(_ lines: [String]) -> FileContent {
        FileContent(marks: Dictionary(uniqueKeysWithValues: lines.indices.map { ($0 + 1, .added) }), lines)
    }
}
