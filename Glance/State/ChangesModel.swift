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
    /// The file shown in the detail pane.
    private(set) var selectedPath: String?
    /// The files selected in the list, including `selectedPath`. More than one after ⌘- or ⇧-clicking.
    private(set) var selectedPaths: Set<String> = []
    /// What the last discard removed, until it's undone or another discard replaces it.
    private(set) var lastDiscard: Discard?

    /// Discarding doesn't ask first, so it keeps what it overwrites.
    struct Discard: Identifiable {
        let id = UUID()
        /// "Discarded 3 files", for the Undo banner.
        let summary: String
        /// Each file's contents before the discard, or `nil` when it didn't exist, as for a deleted file.
        let contents: [String: Data?]
    }
    var viewedPaths: Set<String> = []
    var filter = ""
    /// Shows why git refused to discard or push.
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
            file.stagedHunks = change.stagedHunks
            return file
        }
        let diff = change.hunks.map { hunks in
            FileDiff(change.path, change.status, hunks: hunks.map { RawHunk(oldStart: $0.oldStart, newStart: $0.newStart, context: $0.context, lines: $0.displayLines) })
        } ?? FileDiff(change.path, change.status, additions: 0, deletions: 0)
        let file = ChangedFile(diff: diff, stagedHunks: change.stagedHunks)
        cache[change.path] = (change.hunks, file)
        return file
    }

    private func apply(_ files: [ChangedFile]) {
        let paths = Set(files.map(\.id))
        cache = cache.filter { paths.contains($0.key) }
        self.files = files
        viewedPaths.formIntersection(paths)
        viewedPaths.formUnion(files.filter(\.isViewed).map(\.id))
        selectedPaths.formIntersection(paths)
        if selectedPath.map({ !paths.contains($0) }) ?? true {
            selectedPath = files.first { selectedPaths.contains($0.id) }?.id ?? files.first?.id
        }
        if let selectedPath { selectedPaths.insert(selectedPath) }
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

    var isMultipleSelection: Bool { selectedPaths.count > 1 }

    /// The selected files, in list order.
    var selectedFiles: [ChangedFile] { files.filter { selectedPaths.contains($0.id) } }

    func select(_ file: ChangedFile) {
        selectedPath = file.id
        selectedPaths = [file.id]
    }

    /// Adds the file to the selection, or removes it, as ⌘-clicking does in Finder.
    func toggleSelection(_ file: ChangedFile) {
        guard selectedPaths.contains(file.id) else {
            selectedPaths.insert(file.id)
            selectedPath = file.id
            return
        }
        guard selectedPaths.count > 1 else { return }
        selectedPaths.remove(file.id)
        if selectedPath == file.id { selectedPath = visibleFiles.first { selectedPaths.contains($0.id) }?.id }
    }

    /// Selects the files from the shown one through `file`, as ⇧-clicking does in Finder.
    func extendSelection(to file: ChangedFile) {
        let list = visibleFiles
        guard let anchor = list.firstIndex(where: { $0.id == selectedPath }), let end = list.firstIndex(where: { $0.id == file.id })
        else { return select(file) }
        selectedPaths = Set(list[min(anchor, end)...max(anchor, end)].map(\.id))
    }

    func selectNext() { step(by: 1) }
    func selectPrevious() { step(by: -1) }

    private func step(by offset: Int) {
        let list = visibleFiles
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedPath } ?? (offset > 0 ? -1 : 0)
        select(list[(current + offset + list.count) % list.count])
    }

    // MARK: Discarding

    /// A branch's changes are already committed, so there's nothing to discard or commit.
    var isReadOnly: Bool {
        if case .branch = source { true } else { false }
    }

    /// A new or deleted file is one hunk, so it's discarded as a whole.
    private func isWholeFile(_ file: ChangedFile) -> Bool {
        file.diff.status != .modified || cache[file.id]?.hunks == nil
    }

    /// Puts the hunk back the way it is in `HEAD`, in the working tree and, if an agent staged it, the index. A new
    /// file goes to the Trash.
    func discard(hunk index: Int, in file: ChangedFile) {
        guard !isWholeFile(file) else { return discardFile(file) }
        let isStaged = file.stagedHunks.contains(index)
        let discard = Discard(summary: "Discarded a change in \(file.diff.name)", contents: snapshot([file.id]))
        applyHunk(index, of: file, failure: "Couldn’t Discard Change") { patch in
            [["apply", "-R", "--whitespace=nowarn", patch]] + (isStaged ? [["apply", "--cached", "-R", "--whitespace=nowarn", patch]] : [])
        } onSuccess: {
            self.lastDiscard = discard
        }
    }

    /// Writes the hunk as a patch file and runs each git command `commands` makes from its path, in order.
    private func applyHunk(_ index: Int, of file: ChangedFile, failure: String, commands: @escaping (String) -> [[String]], onSuccess: @escaping () -> Void) {
        guard !isReadOnly, let hunks = cache[file.id]?.hunks, hunks.indices.contains(index) else { return }
        let patch = hunks[index].patch(for: file.id)
        let patchURL = FileManager.default.temporaryDirectory.appending(path: "glance-\(UUID().uuidString).patch")
        Task { [url] in
            do {
                try patch.write(to: patchURL, atomically: true, encoding: .utf8)
                for arguments in commands(patchURL.path) { try await Git.run(arguments, in: url) }
                onSuccess()
            } catch {
                onError(failure, error)
            }
            try? FileManager.default.removeItem(at: patchURL)
            refresh()
        }
    }

    private func discardFile(_ file: ChangedFile) {
        discard([file])
    }

    /// Puts the files back the way they are in `HEAD`, in the working tree and the index. New files go to the Trash.
    func discard(_ files: [ChangedFile]) {
        guard !isReadOnly, !files.isEmpty else { return }
        let added = files.filter { $0.diff.status == .added }.map(\.id)
        let tracked = files.filter { $0.diff.status != .added }.map(\.id)
        let discard = Discard(
            summary: files.count == 1 ? "Discarded \(files[0].diff.name)" : "Discarded \(files.count) files",
            contents: snapshot(files.map(\.id))
        )
        Task { [url] in
            do {
                // `--` keeps a path that looks like an option from being read as one.
                if !tracked.isEmpty { try await Git.run(["checkout", "HEAD", "--"] + tracked, in: url) }
                if !added.isEmpty {
                    try await Git.run(["rm", "--cached", "--force", "--quiet", "--ignore-unmatch", "--"] + added, in: url)
                    for path in added { try FileManager.default.trashItem(at: url.appending(path: path), resultingItemURL: nil) }
                }
                lastDiscard = discard
            } catch {
                onError("Couldn’t Discard Changes", error)
            }
            refresh()
        }
    }

    private func snapshot(_ paths: [String]) -> [String: Data?] {
        Dictionary(uniqueKeysWithValues: paths.map { ($0, try? Data(contentsOf: url.appending(path: $0))) })
    }

    /// Writes back the files the last discard changed, as they were just before it.
    func undoDiscard() {
        guard let discard = lastDiscard else { return }
        lastDiscard = nil
        do {
            for (path, data) in discard.contents {
                let fileURL = url.appending(path: path)
                if let data {
                    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: fileURL)
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        } catch {
            onError("Couldn’t Undo Discard", error)
        }
        refresh()
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

    /// Every selected file is marked as viewed.
    var isSelectionViewed: Bool { !selectedPaths.isEmpty && selectedPaths.isSubset(of: viewedPaths) }

    /// Marks the selected files as viewed, or, when they all are already, as not viewed.
    func toggleViewedForSelection() {
        setViewed(selectedFiles, !isSelectionViewed)
    }

    func setViewed(_ files: [ChangedFile], _ viewed: Bool) {
        let paths = files.map(\.id)
        if viewed { viewedPaths.formUnion(paths) } else { viewedPaths.subtract(paths) }
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
