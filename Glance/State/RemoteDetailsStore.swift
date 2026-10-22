//
//  RemoteDetailsStore.swift
//  Glance
//

import Foundation
import Observation

/// Whether each repository is private or a fork, asked of its Git host without signing in and cached for a day.
@Observable
final class RemoteDetailsStore {
    struct Details: Codable {
        /// A host hides private repositories from anonymous requests, so anything it won't show counts as private.
        let isPrivate: Bool
        /// "owner/name" of the repository this one was forked from.
        let forkParent: String?
        let fetched: Date
    }

    private(set) var details: [String: Details] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    private static let maxAge: TimeInterval = 24 * 60 * 60
    private static let cacheFile = URL.glanceCaches.appending(path: "RemoteDetails.json")

    init() {
        if let data = try? Data(contentsOf: Self.cacheFile),
           let cached = try? JSONDecoder().decode([String: Details].self, from: data) {
            details = cached
        }
    }

    func details(for repository: Repository) -> Details? {
        Self.key(repository).flatMap { details[$0] }
    }

    func load(_ repository: Repository) async {
        guard let host = repository.host, let owner = repository.owner, let name = repository.remoteName,
              let key = Self.key(repository), requested.insert(key).inserted,
              details[key].map({ Date.now.timeIntervalSince($0.fetched) > Self.maxAge }) ?? true,
              let fetched = await Self.fetch(host: host, owner: owner, name: name)
        else { return }

        details[key] = fetched
        if let data = try? JSONEncoder().encode(details) {
            try? FileManager.default.createDirectory(at: URL.glanceCaches, withIntermediateDirectories: true)
            try? data.write(to: Self.cacheFile)
        }
    }

    private static func key(_ repository: Repository) -> String? {
        guard let host = repository.host, let owner = repository.owner, let name = repository.remoteName else { return nil }
        return "\(host)/\(owner)/\(name)".lowercased()
    }

    /// Asks GitHub, GitLab, Bitbucket, or Gitea and Forgejo (Codeberg and most self-hosted servers). `nil` when the
    /// host couldn't be reached, so the repository isn't wrongly marked private.
    private static func fetch(host: String, owner: String, name: String) async -> Details? {
        guard let owner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let name = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        let response: HostAPI.Response?
        let isPrivate: ([String: Any]) -> Bool
        let parent: ([String: Any]) -> String?
        switch host.lowercased() {
        case "github.com", "ssh.github.com":
            response = await HostAPI.get("https://api.github.com/repos/\(owner)/\(name)")
            isPrivate = { $0["private"] as? Bool ?? false }
            parent = { ($0["parent"] as? [String: Any])?["full_name"] as? String }
        case "bitbucket.org":
            response = await HostAPI.get("https://api.bitbucket.org/2.0/repositories/\(owner)/\(name)")
            isPrivate = { $0["is_private"] as? Bool ?? false }
            parent = { ($0["parent"] as? [String: Any])?["full_name"] as? String }
        case let host where host.contains("gitlab"):
            // Projects are addressed by their URL-encoded path; "internal" projects are hidden from anonymous users too.
            response = await HostAPI.get("https://\(host)/api/v4/projects/\(owner)%2F\(name)")
            isPrivate = { $0["visibility"] as? String != "public" }
            parent = { ($0["forked_from_project"] as? [String: Any])?["path_with_namespace"] as? String }
        default:
            response = await HostAPI.get("https://\(host)/api/v1/repos/\(owner)/\(name)")
            isPrivate = { $0["private"] as? Bool ?? false }
            parent = { ($0["parent"] as? [String: Any])?["full_name"] as? String }
        }

        switch response {
        case let .found(json as [String: Any]):
            return Details(isPrivate: isPrivate(json), forkParent: parent(json), fetched: .now)
        case .inaccessible:
            return Details(isPrivate: true, forkParent: nil, fetched: .now)
        default:
            return nil
        }
    }
}
