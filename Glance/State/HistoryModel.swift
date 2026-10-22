//
//  HistoryModel.swift
//  Glance
//

import Foundation
import Observation

@Observable
final class HistoryModel {
    let commits: [Commit]
    var selectedSHA: String?
    var selectedFileIndex = 0
    var filter = ""

    init(commits: [Commit]) {
        self.commits = commits
        selectedSHA = commits.first?.sha
    }

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

    var selectedFile: FileDiff? {
        guard let files = selectedCommit?.files, files.indices.contains(selectedFileIndex) else { return nil }
        return files[selectedFileIndex]
    }

    var unpushedCount: Int { commits.count(where: \.isUnpushed) }

    func select(_ commit: Commit) {
        guard commit.sha != selectedSHA else { return }
        selectedSHA = commit.sha
        selectedFileIndex = 0
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
