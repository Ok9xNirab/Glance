//
//  Repository.swift
//  Glance
//

import Foundation

/// A folder the user added to the sidebar, with the worktrees and branches read from its `.git` directory.
struct Repository: Identifiable {
    let url: URL
    /// The host of the `origin` remote, such as "github.com".
    var host: String?
    /// The account or organization that owns the `origin` remote, or `nil` when the repository is local only.
    var owner: String?
    /// The repository's name on the remote, which can differ from the folder's.
    var remoteName: String?
    var worktrees: [Worktree]
    var branches: [Branch]

    var id: URL { url }
    var name: String { url.lastPathComponent }
    /// The worktree that's checked out in the folder the user added.
    var mainWorktree: Worktree { worktrees[0] }
}

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
    let url: URL
    var isAgentActive = false
    var aheadCount = 0
    var behindCount = 0
    var changes: [ChangedFile] = []

    var id: String { url.path }
    /// The folder, with the home folder abbreviated to "~".
    var path: String { (url.path as NSString).abbreviatingWithTildeInPath }
}

struct Branch: Identifiable {
    let name: String
    /// When the branch last moved, if its reflog says.
    let lastUpdated: Date?
    /// The remote tracking this branch, or `nil` for a local-only branch.
    var remote: String?
    /// Recently used branches are listed in the sidebar.
    var isRecent = false

    var id: String { name }
}
