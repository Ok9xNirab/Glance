//
//  GitRepositoryReader.swift
//  Glance
//

import Foundation

/// Reads worktrees and branches straight from a repository's `.git` directory, which is quicker than running `git`
/// several times on every refresh.
enum GitRepositoryReader {
    enum ReadError: LocalizedError {
        case notARepository(String)
        case linkedWorktree(String)

        var errorDescription: String? {
            switch self {
            case let .notARepository(name):
                "“\(name)” doesn’t contain a Git repository."
            case let .linkedWorktree(name):
                "“\(name)” is a linked worktree. Add the repository’s main folder instead, and its worktrees will be listed with it."
            }
        }
    }

    static func read(_ url: URL) throws -> Repository {
        let name = url.lastPathComponent
        let gitDir = url.appending(path: ".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) else {
            throw ReadError.notARepository(name)
        }
        guard isDirectory.boolValue else { throw ReadError.linkedWorktree(name) }

        let worktrees = [Worktree(name: name, branch: head(in: gitDir), url: url.standardizedFileURL)] + linkedWorktrees(in: gitDir)
        let config = config(in: gitDir)
        let remotes = config.reduce(into: [String: String]()) { remotes, section in
            if let branch = quotedName(section.key, kind: "branch"), let remote = section.value["remote"] { remotes[branch] = remote }
        }

        let remoteNames = config.keys.compactMap { quotedName($0, kind: "remote") }
        let switches = branchSwitches(in: gitDir)
        let branches = branchNames(in: gitDir)
            .map { name in
                Branch(
                    name: name,
                    lastUpdated: lastUpdated(branch: name, in: gitDir),
                    remote: remotes[name],
                    base: base(of: name, in: gitDir, remotes: remoteNames, switches: switches)
                )
            }
            .sorted { ($0.lastUpdated ?? .distantPast, $1.name) > ($1.lastUpdated ?? .distantPast, $0.name) }

        let remote = remoteOwner(config: config)
        return Repository(url: url, host: remote?.host, owner: remote?.owner, remoteName: remote?.name, worktrees: worktrees, branches: branches)
    }

    // MARK: Worktrees

    private static func linkedWorktrees(in gitDir: URL) -> [Worktree] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: gitDir.appending(path: "worktrees"), includingPropertiesForKeys: nil)) ?? []
        return entries
            .compactMap { entry -> Worktree? in
                // `gitdir` holds the path of the worktree's `.git` file, relative to `entry` when Git writes relative paths.
                guard let gitFile = text(at: entry.appending(path: "gitdir")) else { return nil }
                let root = URL(filePath: gitFile, relativeTo: entry).standardizedFileURL.deletingLastPathComponent()
                return Worktree(name: root.lastPathComponent, branch: head(in: entry), url: root)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The branch `HEAD` points at, or the abbreviated commit when it's detached.
    private static func head(in gitDir: URL) -> String {
        guard let head = text(at: gitDir.appending(path: "HEAD")) else { return "unknown" }
        if head.hasPrefix("ref: ") {
            let ref = head.dropFirst("ref: ".count)
            return String(ref.hasPrefix("refs/heads/") ? ref.dropFirst("refs/heads/".count) : ref)
        }
        return "detached at \(head.prefix(7))"
    }

    // MARK: Branches

    private static func branchNames(in gitDir: URL) -> Set<String> {
        var names = Set<String>()

        let heads = gitDir.appending(path: "refs/heads")
        let enumerator = FileManager.default.enumerator(at: heads, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = enumerator?.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            names.insert(file.pathComponents.dropFirst(heads.pathComponents.count).joined(separator: "/"))
        }

        // Lines look like "<sha> refs/heads/<name>"; peeled tags start with "^" and comments with "#".
        for line in text(at: gitDir.appending(path: "packed-refs"))?.split(separator: "\n") ?? [] {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, parts[1].hasPrefix("refs/heads/") {
                names.insert(String(parts[1].dropFirst("refs/heads/".count)))
            }
        }
        return names
    }

    /// When the branch last moved, from the timestamp on the final line of its reflog.
    private static func lastUpdated(branch: String, in gitDir: URL) -> Date? {
        // "<old> <new> Name <email> <seconds> <zone>\t<message>"
        guard let line = text(at: gitDir.appending(path: "logs/refs/heads/\(branch)"))?.split(separator: "\n").last,
              let identity = line.split(separator: "\t", maxSplits: 1).first,
              let seconds = identity.split(separator: " ").dropLast().last.flatMap({ TimeInterval($0) })
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// The branch `branch` was created from. Its reflog starts "branch: Created from main" when it was made from a
    /// named branch, but "Created from HEAD" when it was made with `git switch -c`, so then it's the branch some
    /// worktree switched away from to reach it.
    private static func base(of branch: String, in gitDir: URL, remotes: [String], switches: [String: String]) -> String? {
        guard let line = text(at: gitDir.appending(path: "logs/refs/heads/\(branch)"))?.split(separator: "\n").first,
              let message = line.split(separator: "\t", maxSplits: 1).last,
              message.hasPrefix("branch: Created from ")
        else { return nil }

        var source = String(message.dropFirst("branch: Created from ".count))
        guard source != "HEAD" else { return switches[branch] }
        for prefix in ["refs/heads/", "refs/remotes/"] where source.hasPrefix(prefix) {
            source = String(source.dropFirst(prefix.count))
        }
        // "origin/main" counts as "main"; a branch made from its own remote copy has no base of its own.
        if let remote = remotes.first(where: { source.hasPrefix($0 + "/") }) {
            source = String(source.dropFirst(remote.count + 1))
        }
        return source == branch ? nil : source
    }

    /// For each branch a worktree first switched to, the branch it switched from, read from every worktree's `HEAD`
    /// reflog: "checkout: moving from main to rate-limit".
    private static func branchSwitches(in gitDir: URL) -> [String: String] {
        let linked = (try? FileManager.default.contentsOfDirectory(at: gitDir.appending(path: "worktrees"), includingPropertiesForKeys: nil)) ?? []
        let logs = [gitDir] + linked
        var switches: [String: (from: String, time: TimeInterval)] = [:]
        for log in logs {
            for line in text(at: log.appending(path: "logs/HEAD"))?.split(separator: "\n") ?? [] {
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2, parts[1].hasPrefix("checkout: moving from ") else { continue }
                let names = parts[1].dropFirst("checkout: moving from ".count).components(separatedBy: " to ")
                guard names.count == 2, names[0] != names[1] else { continue }
                let time = parts[0].split(separator: " ").dropLast().last.flatMap { TimeInterval($0) } ?? 0
                // The earliest switch is the one that created the branch.
                if switches[names[1]].map({ time < $0.time }) ?? true {
                    switches[names[1]] = (names[0], time)
                }
            }
        }
        return switches.mapValues(\.from)
    }

    // MARK: Config

    /// `.git/config` as values keyed by section, then by key: `config["branch \"main\""]?["remote"]`.
    private static func config(in gitDir: URL) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var section = ""
        for rawLine in text(at: gitDir.appending(path: "config"))?.split(separator: "\n") ?? [] {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }
            let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 { sections[section, default: [:]][pair[0]] = pair[1] }
        }
        return sections
    }

    /// The name in a section header like `branch "main"`, when the section is of `kind`.
    private static func quotedName(_ section: String, kind: String) -> String? {
        let prefix = "\(kind) \""
        guard section.hasPrefix(prefix), section.hasSuffix("\"") else { return nil }
        return String(section.dropFirst(prefix.count).dropLast())
    }

    /// The host, account or organization, and repository name in the `origin` remote's URL (or the first remote's), such as
    /// github.com and "acme" for `git@github.com:acme/api.git` or `https://github.com/acme/api`. `nil` for local-only repositories.
    private static func remoteOwner(config: [String: [String: String]]) -> (host: String, owner: String, name: String)? {
        let remotes = config.keys.filter { quotedName($0, kind: "remote") != nil }.sorted()
        guard let remote = remotes.first(where: { $0 == "remote \"origin\"" }) ?? remotes.first,
              let url = config[remote]?["url"], !url.hasPrefix("/"), !url.hasPrefix("file:"), !url.hasPrefix(".")
        else { return nil }

        let host: Substring?
        if let scheme = url.range(of: "://") {
            // "https://user@host:port/owner/repo"
            host = url[scheme.upperBound...].split(separator: "/").first?.split(separator: "@").last?.split(separator: ":").first
        } else {
            // scp-like "user@host:owner/repo"
            host = url.split(separator: ":").first?.split(separator: "@").last
        }
        let parts = url.split(whereSeparator: { $0 == "/" || $0 == ":" })
        guard let host, parts.count >= 3 else { return nil }
        let name = parts[parts.count - 1]
        return (String(host), String(parts[parts.count - 2]), String(name.hasSuffix(".git") ? name.dropLast(4) : name))
    }

    // MARK: Helpers

    private static func text(at url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
