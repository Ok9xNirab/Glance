//
//  ChangesModel.swift
//  Glance
//

import Foundation
import Observation

/// Review state for one worktree's uncommitted changes, read from git and refreshed whenever its files change.
@Observable
final class ChangesModel {
    let url: URL
    private(set) var files: [ChangedFile] = []
    /// `false` until git has been read once, so a clean worktree isn't announced before it's known.
    private(set) var isLoaded = false
    private(set) var isCommitting = false
    var selectedPath: String?
    var stagedPaths: Set<String> = []
    var viewedPaths: Set<String> = []
    var filter = ""
    var summary = ""
    var details = ""
    /// Shows why git refused to stage or commit.
    @ObservationIgnored var onError: (String, Error) -> Void = { _, _ in }

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Highlighted diffs from the last read, reused while a file's hunks are unchanged.
    @ObservationIgnored private var cache: [String: (hunks: [WorkingTreeChange.Hunk]?, file: ChangedFile)] = [:]

    init(url: URL) {
        self.url = url
        watcher = FileWatcher(url) { [weak self] in self?.refresh() }
        refresh()
    }

    /// Initial files that aren't read from git, for previews.
    init(files: [ChangedFile]) {
        url = URL(filePath: "/")
        apply(files)
        isLoaded = true
    }

    // MARK: Reading

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [url] in
            do {
                let changes = try await WorkingTreeReader.read(url)
                guard !Task.isCancelled else { return }
                apply(changes.map(changedFile))
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
            return file
        }
        let diff = change.hunks.map { hunks in
            FileDiff(change.path, change.status, hunks: hunks.map { RawHunk(oldStart: $0.oldStart, newStart: $0.newStart, context: $0.context, lines: $0.lines) })
        } ?? FileDiff(change.path, change.status, additions: 0, deletions: 0)
        let file = ChangedFile(diff: diff, isStaged: change.isStaged)
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
        guard !paths.isEmpty else { return }
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

    var canCommit: Bool {
        !stagedPaths.isEmpty && !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCommitting
    }

    /// Commits what's staged with the summary and description as its message, running the user's hooks.
    func commit() {
        guard canCommit else { return }
        let details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        var arguments = ["commit", "--quiet", "-m", summary.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !details.isEmpty { arguments += ["-m", details] }
        isCommitting = true
        Task {
            do {
                try await Git.run(arguments, in: url)
                summary = ""
                self.details = ""
            } catch {
                onError("Couldn’t Commit", error)
            }
            isCommitting = false
            refresh()
        }
    }
}
