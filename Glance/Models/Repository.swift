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

    /// How many branches the sidebar lists under a worktree.
    private static let sidebarBranchLimit = 5

    /// The most recently updated branches that were created from `worktree`'s branch and aren't checked out. Branches
    /// whose origin isn't known, or whose origin isn't checked out anywhere, are listed under the main worktree.
    func sidebarBranches(for worktree: Worktree) -> [Branch] {
        let checkedOut = Set(worktrees.map(\.branch))
        let isMain = worktree.id == mainWorktree.id
        return branches
            .filter { branch in
                guard !checkedOut.contains(branch.name) else { return false }
                guard let base = branch.base, checkedOut.contains(base) else { return isMain }
                return base == worktree.branch
            }
            .prefix(Self.sidebarBranchLimit)
            .map { $0 }
    }
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
    /// The branch this one was created from, when its reflog says.
    var base: String?

    var id: String { name }
}
