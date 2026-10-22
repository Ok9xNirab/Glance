//
//  WorkingTreeReader.swift
//  Glance
//

import Foundation

/// One file's uncommitted change as git reports it, before it's highlighted into a `FileDiff`.
nonisolated struct WorkingTreeChange: Sendable {
    nonisolated struct Hunk: Sendable, Equatable {
        let oldStart: Int
        let newStart: Int
        let context: String
        let lines: [String]
    }

    let path: String
    let status: FileStatus
    /// Every change is in the index, so committing now would include all of it.
    let isStaged: Bool
    /// `nil` for binary files and files too large to show.
    let hunks: [Hunk]?
}

/// Reads a worktree's uncommitted changes, staged and unstaged, compared with `HEAD`.
nonisolated enum WorkingTreeReader {
    /// Untracked files larger than this are listed without their contents.
    private static let untrackedSizeLimit = 1_000_000
    /// The tree of a repository with no commits, to diff against before the first commit.
    private static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    static func read(_ worktree: URL) async throws -> [WorkingTreeChange] {
        // `--no-optional-locks` keeps status from rewriting the index, which would wake the file watcher again.
        let git = ["--no-optional-locks", "-c", "core.quotePath=false"]
        let status = try await Git.run(git + ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames"], in: worktree)
        let entries = parseStatus(status)
        guard !entries.isEmpty else { return [] }

        let base = (try? await Git.run(["rev-parse", "--verify", "--quiet", "HEAD"], in: worktree)) == nil ? emptyTree : "HEAD"
        let diff = try await Git.run(git + ["diff", base, "--no-color", "--no-ext-diff", "--no-renames", "--unified=3"], in: worktree)
        let hunksByPath = parseDiff(diff)

        return entries.map { entry in
            if entry.isUntracked {
                return WorkingTreeChange(path: entry.path, status: .added, isStaged: false, hunks: untrackedHunks(worktree.appending(path: entry.path)))
            }
            let status: FileStatus = entry.code.contains("D") ? .deleted : entry.code.contains("A") ? .added : .modified
            return WorkingTreeChange(path: entry.path, status: status, isStaged: entry.isStaged, hunks: hunksByPath[entry.path] ?? [])
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: Status

    private struct StatusEntry {
        /// The two-letter index and worktree code, such as "M " (staged) or " M" (unstaged).
        let code: String
        let path: String

        var isUntracked: Bool { code == "??" }
        var isStaged: Bool { code.first != " " && code.last == " " }
    }

    /// Entries look like "XY path", separated by NUL bytes.
    private static func parseStatus(_ output: String) -> [StatusEntry] {
        output.split(separator: "\0").compactMap { record in
            guard record.count > 3 else { return nil }
            return StatusEntry(code: String(record.prefix(2)), path: String(record.dropFirst(3)))
        }
    }

    // MARK: Diff

    /// Hunks for each path in a unified diff, or `nil` for a binary file.
    private static func parseDiff(_ output: String) -> [String: [WorkingTreeChange.Hunk]?] {
        var result: [String: [WorkingTreeChange.Hunk]?] = [:]
        var path: String?
        var hunks: [WorkingTreeChange.Hunk] = []
        var isBinary = false
        var current: (oldStart: Int, newStart: Int, context: String, lines: [String])?

        func finishHunk() {
            if let hunk = current { hunks.append(.init(oldStart: hunk.oldStart, newStart: hunk.newStart, context: hunk.context, lines: hunk.lines)) }
            current = nil
        }
        func finishFile() {
            finishHunk()
            if let path { result[path] = isBinary ? .some(nil) : hunks }
            path = nil
            hunks = []
            isBinary = false
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                finishFile()
            } else if current != nil, let first = line.first, first == "+" || first == "-" || first == " " {
                current?.lines.append(String(line))
            } else if line.hasPrefix("@@ ") {
                finishHunk()
                current = parseHunkHeader(line)
            } else if line.hasPrefix("--- a/") {
                path = filePath(line.dropFirst(6))
            } else if line.hasPrefix("+++ b/") {
                path = filePath(line.dropFirst(6))
            } else if line.hasPrefix("Binary files ") {
                isBinary = true
                // "Binary files a/x and b/x differ", or "/dev/null" on one side.
                let names = line.dropFirst("Binary files ".count).dropLast(" differ".count).components(separatedBy: " and ")
                if let name = names.last(where: { $0.hasPrefix("b/") }) ?? names.first(where: { $0.hasPrefix("a/") }) {
                    path = String(name.dropFirst(2))
                }
            }
            // Other lines are headers ("index", "new file mode") or "\ No newline at end of file".
        }
        finishFile()
        return result
    }

    /// Git ends the name with a tab when it contains a space, to match GNU diff.
    private static func filePath(_ text: Substring) -> String {
        String(text.hasSuffix("\t") ? text.dropLast() : text)
    }

    /// "@@ -12,7 +12,9 @@ function name" gives the start lines and the trailing context.
    private static func parseHunkHeader(_ line: Substring) -> (oldStart: Int, newStart: Int, context: String, lines: [String])? {
        let parts = line.split(separator: "@@", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let ranges = parts[1].split(separator: " ")
        guard ranges.count == 2,
              let oldStart = Int(ranges[0].dropFirst().split(separator: ",")[0]),
              let newStart = Int(ranges[1].dropFirst().split(separator: ",")[0])
        else { return nil }
        let context = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
        return (oldStart, newStart, context, [])
    }

    // MARK: Untracked files

    /// A new file's contents as one hunk of additions, or `nil` when it's binary or too large.
    private static func untrackedHunks(_ url: URL) -> [WorkingTreeChange.Hunk]? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= untrackedSizeLimit,
              let data = try? Data(contentsOf: url), !data.contains(0),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        guard !text.isEmpty else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if text.hasSuffix("\n") { lines.removeLast() }
        return [.init(oldStart: 0, newStart: 1, context: "", lines: lines.map { "+" + $0 })]
    }
}
