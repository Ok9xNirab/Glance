//
//  ChangesModel.swift
//  Glance
//

import Foundation
import Observation

/// Review state for one worktree's uncommitted changes, read from git and refreshed whenever its files change, or,
/// read-only, for what a branch changed since it left the main branch.
@Observable
final class ChangesModel {
    enum Source {
        case workingTree
        case branch(name: String, base: String)
    }

    /// The worktree, or for a branch the repository.
    let url: URL
    let source: Source
    private(set) var files: [ChangedFile] = []
    /// `false` until git has been read once, so a clean worktree isn't announced before it's known.
    private(set) var isLoaded = false
    /// How far the branch is ahead of and behind its upstream, or `nil` when it doesn't track one.
    private(set) var upstream: (ahead: Int, behind: Int)?
    private(set) var isPushing = false
    var selectedPath: String?
    var stagedPaths: Set<String> = []
    var viewedPaths: Set<String> = []
    var filter = ""
    /// Shows why git refused to stage, discard or push.
    @ObservationIgnored var onError: (String, Error) -> Void = { _, _ in }

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Highlighted diffs from the last read, reused while a file's hunks are unchanged.
    @ObservationIgnored private var cache: [String: (hunks: [WorkingTreeChange.Hunk]?, file: ChangedFile)] = [:]

    init(url: URL) {
        self.url = url
        source = .workingTree
        watcher = FileWatcher(url) { [weak self] in self?.refresh() }
        refresh()
    }

    init(branch: String, base: String, repository: URL) {
        url = repository
        source = .branch(name: branch, base: base)
        refresh()
    }

    /// Initial files that aren't read from git, for previews.
    init(files: [ChangedFile]) {
        url = URL(filePath: "/")
        source = .workingTree
        apply(files)
        isLoaded = true
    }

    // MARK: Reading

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [url, source] in
            do {
                let changes = switch source {
                case .workingTree: try await WorkingTreeReader.read(url)
                case let .branch(name, base): try await WorkingTreeReader.read(branch: name, base: base, in: url)
                }
                let upstream = isReadOnly ? nil : await WorkingTreeReader.readUpstream(url)
                guard !Task.isCancelled else { return }
                apply(changes.map(changedFile))
                self.upstream = upstream
            } catch {
                guard !Task.isCancelled else { return }
                apply([])
            }
            isLoaded = true
        }
    }

    private func changedFile(_ change: WorkingTreeChange) -> ChangedFile {
        if let cached = cache[change.path], cached.hunks == change.hunks, cached.file.diff.status == change.status {
            var file = cached.file
            file.isStaged = change.isStaged
            file.stagedHunks = change.stagedHunks
            return file
        }
        let diff = change.hunks.map { hunks in
            FileDiff(change.path, change.status, hunks: hunks.map { RawHunk(oldStart: $0.oldStart, newStart: $0.newStart, context: $0.context, lines: $0.displayLines) })
        } ?? FileDiff(change.path, change.status, additions: 0, deletions: 0)
        let file = ChangedFile(diff: diff, isStaged: change.isStaged, stagedHunks: change.stagedHunks)
        cache[change.path] = (change.hunks, file)
        return file
    }

    private func apply(_ files: [ChangedFile]) {
        let paths = Set(files.map(\.id))
        cache = cache.filter { paths.contains($0.key) }
        self.files = files
        stagedPaths = Set(files.filter(\.isStaged).map(\.id))
        viewedPaths.formIntersection(paths)
        viewedPaths.formUnion(files.filter(\.isViewed).map(\.id))
        if selectedPath.map({ !paths.contains($0) }) ?? true {
            selectedPath = files.first?.id
        }
    }

    // MARK: Navigating

    var visibleFiles: [ChangedFile] {
        guard !filter.isEmpty else { return files }
        return files.filter { $0.diff.path.localizedCaseInsensitiveContains(filter) }
    }

    var selectedFile: ChangedFile? {
        files.first { $0.id == selectedPath }
    }

    /// 1-based position of the selected file, for "3 of 7".
    var selectedPosition: Int? {
        files.firstIndex { $0.id == selectedPath }.map { $0 + 1 }
    }

    var totalAdditions: Int { files.reduce(0) { $0 + $1.diff.additions } }
    var totalDeletions: Int { files.reduce(0) { $0 + $1.diff.deletions } }

    func select(_ file: ChangedFile) {
        selectedPath = file.id
    }

    func selectNext() { step(by: 1) }
    func selectPrevious() { step(by: -1) }

    private func step(by offset: Int) {
        let list = visibleFiles
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedPath } ?? (offset > 0 ? -1 : 0)
        selectedPath = list[(current + offset + list.count) % list.count].id
    }

    // MARK: Staging

    /// A branch's changes are already committed, so there's nothing to stage or commit.
    var isReadOnly: Bool {
        if case .branch = source { true } else { false }
    }

    var allStaged: Bool { !files.isEmpty && stagedPaths.count == files.count }

    func isStaged(_ file: ChangedFile) -> Bool { stagedPaths.contains(file.id) }

    func setStaged(_ file: ChangedFile, _ staged: Bool) {
        setStaged([file.id], staged)
    }

    func toggleAllStaged() {
        setStaged(files.map(\.id), !allStaged)
    }

    /// Updates the checkboxes straight away, then stages or unstages the paths and reads git again.
    private func setStaged(_ paths: [String], _ staged: Bool) {
        guard !paths.isEmpty, !isReadOnly else { return }
        if staged { stagedPaths.formUnion(paths) } else { stagedPaths.subtract(paths) }
        // `--` keeps a path that looks like an option from being read as one.
        let arguments = staged ? ["add", "--all", "--"] : ["reset", "--quiet", "--"]
        Task {
            do {
                try await Git.run(arguments + paths, in: url)
            } catch {
                onError(staged ? "Couldn’t Stage Files" : "Couldn’t Unstage Files", error)
            }
            refresh()
        }
    }

    // MARK: Hunks

    /// A new or deleted file is one hunk, so it's staged and discarded as a whole.
    private func isWholeFile(_ file: ChangedFile) -> Bool {
        file.diff.status != .modified || cache[file.id]?.hunks == nil
    }

    func isStaged(hunk index: Int, in file: ChangedFile) -> Bool {
        isWholeFile(file) ? isStaged(file) : file.stagedHunks.contains(index)
    }

    func toggleStaged(hunk index: Int, in file: ChangedFile) {
        guard !isWholeFile(file) else { return setStaged(file, !isStaged(file)) }
        let reverse = isStaged(hunk: index, in: file)
        applyHunk(index, of: file, failure: reverse ? "Couldn’t Unstage Hunk" : "Couldn’t Stage Hunk") { patch in
            [["apply", "--cached", "--whitespace=nowarn"] + (reverse ? ["-R"] : []) + [patch]]
        }
    }

    /// Puts the hunk back the way it is in `HEAD`, in the working tree and, if it's staged, the index. A new file
    /// goes to the Trash.
    func discard(hunk index: Int, in file: ChangedFile) {
        guard !isWholeFile(file) else { return discardFile(file) }
        let isStaged = isStaged(hunk: index, in: file)
        applyHunk(index, of: file, failure: "Couldn’t Discard Hunk") { patch in
            [["apply", "-R", "--whitespace=nowarn", patch]] + (isStaged ? [["apply", "--cached", "-R", "--whitespace=nowarn", patch]] : [])
        }
    }

    /// Writes the hunk as a patch file and runs each git command `commands` makes from its path, in order.
    private func applyHunk(_ index: Int, of file: ChangedFile, failure: String, commands: @escaping (String) -> [[String]]) {
        guard !isReadOnly, let hunks = cache[file.id]?.hunks, hunks.indices.contains(index) else { return }
        let patch = hunks[index].patch(for: file.id)
        let patchURL = FileManager.default.temporaryDirectory.appending(path: "glance-\(UUID().uuidString).patch")
        Task { [url] in
            do {
                try patch.write(to: patchURL, atomically: true, encoding: .utf8)
                for arguments in commands(patchURL.path) { try await Git.run(arguments, in: url) }
            } catch {
                onError(failure, error)
            }
            try? FileManager.default.removeItem(at: patchURL)
            refresh()
        }
    }

    private func discardFile(_ file: ChangedFile) {
        guard !isReadOnly else { return }
        Task { [url] in
            do {
                if file.diff.status == .added {
                    try await Git.run(["rm", "--cached", "--force", "--quiet", "--ignore-unmatch", "--", file.id], in: url)
                    try FileManager.default.trashItem(at: url.appending(path: file.id), resultingItemURL: nil)
                } else {
                    try await Git.run(["checkout", "HEAD", "--", file.id], in: url)
                }
            } catch {
                onError("Couldn’t Discard Changes", error)
            }
            refresh()
        }
    }

    // MARK: Pushing

    /// Pushes the branch, setting `origin` as its upstream the first time.
    func push() {
        guard !isReadOnly, !isPushing else { return }
        isPushing = true
        Task { [url, upstream] in
            do {
                try await Git.run(upstream == nil ? ["push", "--set-upstream", "origin", "HEAD"] : ["push"], in: url)
            } catch {
                onError("Couldn’t Push", error)
            }
            isPushing = false
            refresh()
        }
    }

    // MARK: Review

    func isViewed(_ file: ChangedFile) -> Bool { viewedPaths.contains(file.id) }

    func toggleViewedForSelection() {
        guard let selectedPath else { return }
        if viewedPaths.contains(selectedPath) { viewedPaths.remove(selectedPath) } else { viewedPaths.insert(selectedPath) }
    }

    var reviewProgress: Double {
        files.isEmpty ? 0 : Double(viewedPaths.count) / Double(files.count)
    }

    // MARK: Committing

    /// Files marked as viewed, in list order.
    var reviewedFiles: [ChangedFile] { files.filter(isViewed) }

    /// Asks an agent to commit just the reviewed files. Glance leaves committing to the agent.
    var commitPrompt: String {
        let paths = reviewedFiles.map { "- `\($0.diff.path)`" }.joined(separator: "\n")
        return """
            Commit only these files in \(url.path), which I've reviewed:

            \(paths)

            Leave every other change uncommitted, and write a commit message that describes these changes.
            """
    }
}
