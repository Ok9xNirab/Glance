//
//  Commit.swift
//  Glance
//

import SwiftUI

struct Author: Hashable {
    let name: String
    /// Used to find the committer's avatar.
    var email = ""
    let initial: String
    let color: Color
}

extension Author {
    /// The same email always gets the same color. `String.hashValue` changes between launches, so sum the scalars.
    init(name: String, email: String) {
        let sum = email.lowercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
        self.init(name: name, email: email, initial: name.prefix(1).uppercased(), color: Palette.owners[sum % Palette.owners.count])
    }
}

/// An agent credited in a commit's `Co-authored-by` trailer.
nonisolated struct CommitAgent: Hashable, Sendable {
    /// "Claude", "Codex" or "Copilot".
    let product: String
    /// The name as the trailer gives it, such as "Claude Opus 5.5 (1M context)".
    let credit: String

    /// The credit without notes in parentheses, such as "Claude Opus 5.5".
    var name: String {
        credit.split(separator: "(")[0].trimmingCharacters(in: .whitespaces)
    }
}

/// A commit in the history list. Its files are read separately, when it's selected.
struct Commit: Identifiable {
    let sha: String
    let title: String
    var body = ""
    let author: Author
    let date: Date
    var agents: [CommitAgent] = []
    var isUnpushed = false
    var tag: String?
    /// Marks the newest commit that's already on the remote branch.
    var startsRemoteHistory = false

    var id: String { sha }
    var shortSHA: String { String(sha.prefix(7)) }

    /// "18 min", "Yesterday", "3 days" or "Mar 4".
    var relativeTime: String {
        let calendar = Calendar.current
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if calendar.isDateInToday(date) { return "\(Int(seconds / 3600)) hr" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        if days < 7 { return "\(days) days" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) { return date.formatted(.dateTime.month(.abbreviated).day()) }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Today at 6:15 AM", "Monday at 11:03 AM" or "Mar 4, 2025 at 9:30 PM".
    var formattedDate: String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        let day = switch days {
        case 0: "Today"
        case 1: "Yesterday"
        case 2..<7: date.formatted(.dateTime.weekday(.wide))
        default: date.formatted(date: .abbreviated, time: .omitted)
        }
        return "\(day) at \(time)"
    }

    /// The commit message followed by each file's diff, ready to paste into an agent prompt.
    func agentText(files: [FileDiff]) -> String {
        let message = body.isEmpty ? title : "\(title)\n\n\(body)"
        let patches = files.filter { $0.hunks != nil }.map(\.patch)
        return ([message] + patches).joined(separator: "\n\n")
    }
}
