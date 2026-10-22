//
//  Commit.swift
//  Glance
//

import SwiftUI

struct Author: Hashable {
    let name: String
    let initial: String
    let color: Color
}

struct Commit: Identifiable {
    let title: String
    var body = ""
    let author: Author
    var isAgentCoAuthored = false
    let relativeTime: String
    let date: String
    let sha: String
    var isUnpushed = false
    var tag: String?
    /// Marks the newest commit that's already on the remote branch.
    var startsRemoteHistory = false
    let files: [FileDiff]

    var id: String { sha }
    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }

    /// The commit message followed by each file's diff, ready to paste into an agent prompt.
    var agentText: String {
        let message = body.isEmpty ? title : "\(title)\n\n\(body)"
        let patches = files.filter { $0.hunks != nil }.map(\.patch)
        return ([message] + patches).joined(separator: "\n\n")
    }
}
