//
//  FileTree.swift
//  Glance
//

import Foundation

struct FileNode: Identifiable {
    let name: String
    let path: String
    /// `nil` for files.
    let children: [FileNode]?

    var id: String { path }
    var isFolder: Bool { children != nil }
    var parentPath: String { String(path.pathDirectory.dropLast()) }

    /// A tree of repository-relative file paths, folders first, each level in Finder order.
    static func build(_ paths: Set<String>) -> [FileNode] {
        final class Folder {
            var folders: [String: Folder] = [:]
            var files: [String] = []
        }

        let root = Folder()
        for path in paths {
            var folder = root
            let parts = path.split(separator: "/")
            for part in parts.dropLast() {
                let name = String(part)
                if let child = folder.folders[name] {
                    folder = child
                } else {
                    let child = Folder()
                    folder.folders[name] = child
                    folder = child
                }
            }
            if let name = parts.last { folder.files.append(String(name)) }
        }

        func nodes(_ folder: Folder, parent: String) -> [FileNode] {
            func path(_ name: String) -> String { parent.isEmpty ? name : "\(parent)/\(name)" }
            let ordered = { (names: [String]) in names.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
            let folders = ordered(Array(folder.folders.keys)).map { name in
                FileNode(name: name, path: path(name), children: nodes(folder.folders[name]!, parent: path(name)))
            }
            let files = ordered(folder.files).map { FileNode(name: $0, path: path($0), children: nil) }
            return folders + files
        }
        return nodes(root, parent: "")
    }

    /// Every file under `nodes`, depth first.
    static func flatten(_ nodes: [FileNode]) -> [FileNode] {
        nodes.flatMap { node in node.children.map { flatten($0) } ?? [node] }
    }
}

/// A file's text as the editor shows it.
nonisolated struct FileContent: Sendable, Equatable {
    nonisolated enum Mark: Sendable, Equatable {
        case added, modified
    }

    let lines: [String]
    /// Uncommitted-change markers keyed by 1-based line number.
    var marks: [Int: Mark] = [:]
    /// "Spaces: 2" or "Tabs", or `nil` when no line is indented.
    let indentation: String?
    /// "LF" or "CRLF".
    let lineEnding: String

    init(_ text: String) {
        let isCRLF = text.contains("\r\n")
        // "\r\n" is a single Character, so it has to become "\n" before splitting.
        let text = isCRLF ? text.replacingOccurrences(of: "\r\n", with: "\n") : text
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") { lines.removeLast() }
        self.lines = lines
        lineEnding = isCRLF ? "CRLF" : "LF"
        indentation = Self.indentation(of: lines)
    }

    /// Tabs when more lines start with a tab than with spaces, otherwise the narrowest indent that several lines use.
    private static func indentation(of lines: [String]) -> String? {
        var tabbed = 0
        var widths: [Int: Int] = [:]
        for line in lines {
            if line.hasPrefix("\t") {
                tabbed += 1
                continue
            }
            let spaces = line.prefix { $0 == " " }.count
            // " * " continues a block comment rather than indenting.
            guard spaces > 0, spaces < line.count, line.dropFirst(spaces).first != "*" else { continue }
            widths[spaces, default: 0] += 1
        }
        if tabbed > 0, tabbed >= widths.values.reduce(0, +) { return "Tabs" }
        guard let width = widths.filter({ $0.value > 1 }).keys.min() ?? widths.keys.min() else { return nil }
        return "Spaces: \(width)"
    }
}

/// A file read for the editor, or why it can't be shown.
nonisolated enum LoadedFile: Sendable, Equatable {
    case text(FileContent)
    case unavailable(String)
}
