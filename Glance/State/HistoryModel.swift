//
//  HistoryModel.swift
//  Glance
//

import Foundation
import Observation

/// The commits on a worktree's branch, read from git and refreshed when it commits, or, for a branch without a
/// worktree, the commits on that branch.
@Observable
final class HistoryModel {
    /// The worktree, or for a branch the repository.
    let url: URL
    /// `HEAD`, or the branch's name.
    let revision: String
    private(set) var commits: [Commit] = []
    /// `false` until git has been read once, so an empty history isn't announced before it's known.
    private(set) var isLoaded = false
    /// The branch the remote divider is labelled with, such as "origin/main".
    private(set) var upstream: String?
    /// The selected commit's changes, or `nil` while they're read.
    private(set) var selectedChanges: [WorkingTreeChange]?
    var selectedSHA: String?
    var selectedFileIndex = 0
    var filter = ""

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    /// Changes of recently selected commits, newest last, so going back to one doesn't read git again.
    @ObservationIgnored private var recentChanges: [(sha: String, changes: [WorkingTreeChange])] = []
    /// The highlighted diff of the file last shown. Only the shown file is highlighted, since a commit can touch
    /// thousands.
    @ObservationIgnored private var highlighted: (key: String, file: FileDiff)?

    init(url: URL, revision: String = "HEAD", watches: Bool = true) {
        self.url = url
        self.revision = revision
        if watches { watcher = FileWatcher(url) { [weak self] in self?.refresh() } }
        refresh()
    }

    // MARK: Reading

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [url, revision] in
            let result = try? await CommitLogReader.read(revision, in: url)
            guard !Task.isCancelled else { return }
            apply(result?.commits ?? [], upstream: result?.upstream)
            isLoaded = true
        }
    }

    private func apply(_ logged: [LoggedCommit], upstream: String?) {
        var commits = logged.map { commit in
            Commit(
                sha: commit.sha,
                title: commit.subject,
                body: commit.body,
                author: Author(name: commit.authorName, email: commit.authorEmail),
                date: commit.date,
                agents: commit.agents,
                isUnpushed: commit.isUnpushed,
                tag: commit.tag
            )
        }
        if commits.first?.isUnpushed == true, let index = commits.firstIndex(where: { !$0.isUnpushed }) {
            commits[index].startsRemoteHistory = true
        }
        self.commits = commits
        self.upstream = upstream
        if !commits.contains(where: { $0.sha == selectedSHA }) {
            selectedSHA = commits.first?.sha
            selectedFileIndex = 0
            loadSelectedChanges()
        } else if selectedChanges == nil {
            loadSelectedChanges()
        }
    }

    private func loadSelectedChanges() {
        changesTask?.cancel()
        guard let sha = selectedSHA else { return selectedChanges = [] }
        if let recent = recentChanges.first(where: { $0.sha == sha }) { return selectedChanges = recent.changes }
        selectedChanges = nil
        changesTask = Task { [url] in
            let changes = (try? await WorkingTreeReader.read(commit: sha, in: url)) ?? []
            guard !Task.isCancelled else { return }
            recentChanges.append((sha, changes))
            if recentChanges.count > 20 { recentChanges.removeFirst() }
            selectedChanges = changes
        }
    }

    // MARK: Navigating

    var visibleCommits: [Commit] {
        guard !filter.isEmpty else { return commits }
        return commits.filter {
            $0.title.localizedCaseInsensitiveContains(filter)
                || $0.author.name.localizedCaseInsensitiveContains(filter)
                || $0.sha.hasPrefix(filter.lowercased())
        }
    }

    var selectedCommit: Commit? {
        commits.first { $0.sha == selectedSHA }
    }

    /// The selected commit's files with their line counts, or `nil` while they're read.
    var selectedFiles: [FileDiff]? {
        selectedChanges?.map { change in
            let lines = change.hunks?.flatMap(\.displayLines) ?? []
            return FileDiff(change.path, change.status, additions: lines.count { $0.first == "+" }, deletions: lines.count { $0.first == "-" })
        }
    }

    /// The shown file, highlighted.
    var selectedFile: FileDiff? {
        guard let sha = selectedSHA, let changes = selectedChanges, changes.indices.contains(selectedFileIndex) else { return nil }
        let change = changes[selectedFileIndex]
        let key = "\(sha)\n\(change.path)"
        if let highlighted, highlighted.key == key { return highlighted.file }
        let file = diff(change)
        highlighted = (key, file)
        return file
    }

    private func diff(_ change: WorkingTreeChange) -> FileDiff {
        guard let hunks = change.hunks else { return FileDiff(change.path, change.status, additions: 0, deletions: 0) }
        return FileDiff(change.path, change.status, hunks: hunks.map { RawHunk(oldStart: $0.oldStart, newStart: $0.newStart, context: $0.context, lines: $0.displayLines) })
    }

    /// The selected commit's message and diff, ready to paste into an agent prompt.
    var agentText: String? {
        guard let commit = selectedCommit, let changes = selectedChanges else { return nil }
        return commit.agentText(files: changes.map(diff))
    }

    var unpushedCount: Int { commits.count(where: \.isUnpushed) }

    func select(_ commit: Commit) {
        guard commit.sha != selectedSHA else { return }
        selectedSHA = commit.sha
        selectedFileIndex = 0
        loadSelectedChanges()
    }

    func selectNext() { step(by: 1) }
    func selectPrevious() { step(by: -1) }

    private func step(by offset: Int) {
        let list = visibleCommits
        guard let current = list.firstIndex(where: { $0.sha == selectedSHA }) else {
            if let first = list.first { select(first) }
            return
        }
        let next = current + offset
        if list.indices.contains(next) { select(list[next]) }
    }
}
