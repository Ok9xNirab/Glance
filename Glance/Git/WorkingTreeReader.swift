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
        /// Prefixed with `+`, `-` or a space, plus git's "\ No newline at end of file" markers, so the hunk can be
        /// written back out as a patch.
        let lines: [String]

        /// The lines to show, without the markers.
        var displayLines: [String] { lines.filter { !$0.hasPrefix("\\") } }

        /// A patch of just this hunk, for `git apply`.
        func patch(for path: String) -> String {
            let oldCount = lines.count { $0.first == " " || $0.first == "-" }
            let newCount = lines.count { $0.first == " " || $0.first == "+" }
            // Git ends a name containing a space with a tab, so the tab is where it stops reading.
            let name = path.contains(" ") ? path + "\t" : path
            return """
                diff --git a/\(path) b/\(path)
                --- a/\(name)
                +++ b/\(name)
                @@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@
                \(lines.joined(separator: "\n"))

                """
        }
    }

    let path: String
    let status: FileStatus
    /// Every change is in the index, so committing now would include all of it.
    let isStaged: Bool
    /// The positions of the hunks that are in the index exactly as shown.
    var stagedHunks: Set<Int> = []
    /// `nil` for binary files and files too large to show.
    let hunks: [Hunk]?
}

/// Reads a worktree's uncommitted changes, staged and unstaged, compared with `HEAD`, or the changes a branch
/// made since it left another.
nonisolated enum WorkingTreeReader {
    /// Untracked files larger than this are listed without their contents.
    private static let untrackedSizeLimit = 1_000_000
    /// The tree of a repository with no commits, to diff against before the first commit.
    private static let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    /// `--no-optional-locks` keeps status from rewriting the index, which would wake the file watcher again.
    private static let git = ["--no-optional-locks", "-c", "core.quotePath=false"]
    private static let diffOptions = ["--no-color", "--no-ext-diff", "--no-renames", "--unified=3"]

    static func read(_ worktree: URL) async throws -> [WorkingTreeChange] {
        let status = try await Git.run(git + ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--no-renames"], in: worktree)
        let entries = parseStatus(status)
        guard !entries.isEmpty else { return [] }

        let base = (try? await Git.run(["rev-parse", "--verify", "--quiet", "HEAD"], in: worktree)) == nil ? emptyTree : "HEAD"
        async let diff = Git.run(git + ["diff", base] + diffOptions, in: worktree)
        async let stagedDiff = Git.run(git + ["diff", "--cached", base] + diffOptions, in: worktree)
        let hunksByPath = try await parseDiff(diff).mapValues(\.hunks)
        let stagedHunksByPath = try await parseDiff(stagedDiff).mapValues(\.hunks)

        return entries.map { entry in
            if entry.isUntracked {
                return WorkingTreeChange(path: entry.path, status: .added, isStaged: false, hunks: untrackedHunks(worktree.appending(path: entry.path)))
            }
            let status: FileStatus = entry.code.contains("D") ? .deleted : entry.code.contains("A") ? .added : .modified
            let hunks = hunksByPath[entry.path] ?? []
            let staged = stagedHunksByPath[entry.path].flatMap(\.self) ?? []
            let stagedHunks = hunks.map { hunks in hunks.indices.filter { staged.contains(hunks[$0]) } } ?? []
            return WorkingTreeChange(path: entry.path, status: status, isStaged: entry.isStaged, stagedHunks: Set(stagedHunks), hunks: hunks)
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// What `branch` changed since it split from `base`, the way a pull request into `base` would show it.
    static func read(branch: String, base: String, in repository: URL) async throws -> [WorkingTreeChange] {
        // `--` after the range keeps a branch named like a file from being read as a path.
        let diff = try await Git.run(git + ["diff", "\(base)...\(branch)"] + diffOptions + ["--"], in: repository)
        return parseDiff(diff)
            .map { WorkingTreeChange(path: $0.key, status: $0.value.status, isStaged: false, hunks: $0.value.hunks) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// What `commit` changed. A merge is compared with its first parent, the branch it was merged into.
    static func read(commit: String, in repository: URL) async throws -> [WorkingTreeChange] {
        let diff = try await Git.run(git + ["show", "--format=", "--diff-merges=first-parent"] + diffOptions + [commit, "--"], in: repository)
        return parseDiff(diff)
            .map { WorkingTreeChange(path: $0.key, status: $0.value.status, isStaged: false, hunks: $0.value.hunks) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// How many commits `HEAD` is ahead of and behind its upstream, or `nil` when the branch doesn't track one.
    static func readUpstream(_ worktree: URL) async -> (ahead: Int, behind: Int)? {
        guard let output = try? await Git.run(git + ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], in: worktree)
        else { return nil }
        let counts = output.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        return counts.count == 2 ? (counts[0], counts[1]) : nil
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

    /// The status and hunks of each path in a unified diff, with `nil` hunks for a binary file.
    private static func parseDiff(_ output: String) -> [String: (status: FileStatus, hunks: [WorkingTreeChange.Hunk]?)] {
        var result: [String: (status: FileStatus, hunks: [WorkingTreeChange.Hunk]?)] = [:]
        var path: String?
        var status = FileStatus.modified
        var hunks: [WorkingTreeChange.Hunk] = []
        var isBinary = false
        var current: (oldStart: Int, newStart: Int, context: String, lines: [String])?

        func finishHunk() {
            if let hunk = current { hunks.append(.init(oldStart: hunk.oldStart, newStart: hunk.newStart, context: hunk.context, lines: hunk.lines)) }
            current = nil
        }
        func finishFile() {
            finishHunk()
            if let path { result[path] = (status, isBinary ? nil : hunks) }
            path = nil
            status = .modified
            hunks = []
            isBinary = false
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                finishFile()
            } else if current != nil, let first = line.first, first == "+" || first == "-" || first == " " || first == "\\" {
                current?.lines.append(String(line))
            } else if line.hasPrefix("@@ ") {
                finishHunk()
                current = parseHunkHeader(line)
            } else if line.hasPrefix("new file mode") {
                status = .added
            } else if line.hasPrefix("deleted file mode") {
                status = .deleted
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
            // Other lines are headers, such as "index".
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
