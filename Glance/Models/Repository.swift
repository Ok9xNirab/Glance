//
//  Repository.swift
//  Glance
//

import Foundation

struct ChangedFile: Identifiable {
    let diff: FileDiff
    /// How long ago an agent last wrote this file, while it's still being edited.
    var agentEditedAgo: String?
    var isStaged = false
    var isViewed = false

    var id: String { diff.path }
}

struct Worktree: Identifiable {
    let name: String
    let branch: String
    let path: String
    var isAgentActive = false
    var aheadCount = 0
    var behindCount = 0
    var changes: [ChangedFile] = []

    var id: String { name }
}

struct Branch: Identifiable {
    let name: String
    let lastUpdated: String
    /// The remote tracking this branch, or `nil` for a local-only branch.
    var remote: String?
    /// Recently used branches are listed in the sidebar.
    var isRecent = false

    var id: String { name }
}
