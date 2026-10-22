//
//  ChangesModel.swift
//  Glance
//

import Foundation
import Observation

/// Review state for one worktree's uncommitted changes.
@Observable
final class ChangesModel {
    let files: [ChangedFile]
    var selectedPath: String?
    var stagedPaths: Set<String>
    var viewedPaths: Set<String>
    var filter = ""
    var summary = ""
    var details = ""

    init(files: [ChangedFile]) {
        self.files = files
        selectedPath = files.first?.id
        stagedPaths = Set(files.filter(\.isStaged).map(\.id))
        viewedPaths = Set(files.filter(\.isViewed).map(\.id))
    }

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
        if staged { stagedPaths.insert(file.id) } else { stagedPaths.remove(file.id) }
    }

    func toggleAllStaged() {
        stagedPaths = allStaged ? [] : Set(files.map(\.id))
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

    var canCommit: Bool { !stagedPaths.isEmpty }

    /// Static flow: committing only clears the message fields.
    func commit() {
        summary = ""
        details = ""
    }
}
