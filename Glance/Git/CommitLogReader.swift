//
//  CommitLogReader.swift
//  Glance
//

import Foundation

/// One commit as `git log` reports it, before it's turned into a `Commit`.
nonisolated struct LoggedCommit: Sendable {
    let sha: String
    let authorName: String
    let authorEmail: String
    let date: Date
    let subject: String
    /// The message after the subject, without the trailers that credit an agent.
    let body: String
    /// The agents credited in `Co-authored-by` trailers.
    let agents: [CommitAgent]
    let tag: String?
    /// Not on any remote yet.
    let isUnpushed: Bool
}

/// Reads the newest commits on a branch, and which of them haven't been pushed.
nonisolated enum CommitLogReader {
    /// Only this many commits are listed, so a long history reads quickly.
    static let limit = 500

    /// Words in a `Co-authored-by` trailer that mark a commit as written with an agent, and the agent's name.
    /// The first match wins, so "Claude <noreply@anthropic.com>" and "Codex <noreply@openai.com>" each match
    /// their own name before the email.
    private static let agentProducts = [
        ("claude", "Claude"), ("codex", "Codex"), ("copilot", "Copilot"), ("cursor", "Cursor"), ("gemini", "Gemini"),
        ("aider", "Aider"), ("devin", "Devin"), ("jules", "Jules"), ("anthropic", "Claude"), ("openai", "Codex"),
    ]

    private static let git = ["--no-optional-locks", "-c", "core.quotePath=false"]

    /// The commits reachable from `revision`, newest first, and the name of its upstream branch, if it tracks one.
    static func read(_ revision: String, in repository: URL) async throws -> (commits: [LoggedCommit], upstream: String?) {
        // Fields are separated by the unit separator and, with `-z`, commits by NUL.
        let format = ["%H", "%an", "%ae", "%at", "%D", "%s", "%b"].joined(separator: "%x1f")
        async let log = Git.run(git + ["log", "-z", "--max-count=\(limit)", "--decorate-refs=refs/tags/", "--format=\(format)", revision, "--"], in: repository)
        async let unpushed = unpushedSHAs(revision, in: repository)
        async let upstream = try? Git.run(git + ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "\(revision)@{upstream}"], in: repository)

        let unpushedSHAs = await unpushed
        let commits = try await log.split(separator: "\0").compactMap { record -> LoggedCommit? in
            let fields = record.split(separator: "\u{1F}", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7, let seconds = TimeInterval(fields[3]) else { return nil }
            let sha = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let (body, agents) = removingAgentTrailers(fields[6])
            return LoggedCommit(
                sha: sha,
                authorName: fields[1],
                authorEmail: fields[2],
                date: Date(timeIntervalSince1970: seconds),
                subject: fields[5],
                body: body,
                agents: agents,
                tag: tag(in: fields[4]),
                isUnpushed: unpushedSHAs.contains(sha)
            )
        }
        let name = await upstream?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (commits, name?.isEmpty == false ? name : nil)
    }

    /// Commits on `revision` that no remote branch has. A repository without remotes has nothing to push to, so
    /// nothing counts as unpushed.
    private static func unpushedSHAs(_ revision: String, in repository: URL) async -> Set<String> {
        guard let remotes = try? await Git.run(["for-each-ref", "--count=1", "--format=%(refname)", "refs/remotes"], in: repository),
              !remotes.isEmpty,
              let output = try? await Git.run(git + ["rev-list", "--max-count=\(limit)", revision, "--not", "--remotes"], in: repository)
        else { return [] }
        return Set(output.split(separator: "\n").map(String.init))
    }

    /// "tag: v2.4.0, tag: latest" gives "v2.4.0".
    private static func tag(in decorations: String) -> String? {
        decorations.components(separatedBy: ", ")
            .first { $0.hasPrefix("tag: ") }
            .map { String($0.dropFirst("tag: ".count)) }
    }

    /// The chip names the agents that co-authored the commit, so their trailers and the "Generated with" line
    /// that usually comes with them are left out of the body.
    private static func removingAgentTrailers(_ body: String) -> (body: String, agents: [CommitAgent]) {
        var agents: [CommitAgent] = []
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let lowercased = line.lowercased()
            let product = agentProducts.first { lowercased.contains($0.0) }?.1
            if lowercased.hasPrefix("co-authored-by:"), let product {
                // "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>" credits "Claude Opus 5.5 (1M context)".
                let credit = line.dropFirst("co-authored-by:".count).split(separator: "<")[0].trimmingCharacters(in: .whitespaces)
                if !agents.contains(where: { $0.product == product }) {
                    agents.append(CommitAgent(product: product, credit: credit.isEmpty ? product : credit))
                }
                return false
            }
            return !(lowercased.hasPrefix("🤖 generated with") && product != nil)
        }
        return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), agents)
    }
}
