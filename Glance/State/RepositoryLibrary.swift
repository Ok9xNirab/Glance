//
//  RepositoryLibrary.swift
//  Glance
//

import Foundation
import Observation

/// The repositories added to Glance and what's cached about them, shared by every window.
@Observable
final class RepositoryLibrary {
    private(set) var repositories: [Repository] = []
    /// Repository paths, most recently opened first.
    private(set) var recentRepositoryPaths = UserDefaults.standard.stringArray(forKey: recentRepositoriesKey) ?? []
    private static let recentRepositoriesKey = "recentRepositoryPaths"

    let avatars = AvatarStore()
    let remoteDetails = RemoteDetailsStore()

    init() {
        for url in RepositoryBookmarks.restore() {
            if let repository = try? GitRepositoryReader.read(url) { repositories.append(repository) }
        }
    }

    var recentRepositories: [Repository] {
        recentRepositoryPaths.compactMap { path in repositories.first { $0.url.path == path } }
    }

    func noteOpened(_ repository: Repository) {
        recentRepositoryPaths.removeAll { $0 == repository.url.path }
        recentRepositoryPaths.insert(repository.url.path, at: 0)
        UserDefaults.standard.set(recentRepositoryPaths, forKey: Self.recentRepositoriesKey)
    }

    /// Adds the repository in `url`, or returns the one already added there.
    func add(_ url: URL) throws -> Repository {
        if let existing = repositories.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            return existing
        }
        let repository = try GitRepositoryReader.read(url)
        repositories.append(repository)
        RepositoryBookmarks.save(repositories.map(\.url))
        return repository
    }

    func remove(_ repository: Repository) {
        repositories.removeAll { $0.id == repository.id }
        RepositoryBookmarks.save(repositories.map(\.url))
        repository.url.stopAccessingSecurityScopedResource()
        recentRepositoryPaths.removeAll { $0 == repository.url.path }
        UserDefaults.standard.set(recentRepositoryPaths, forKey: Self.recentRepositoriesKey)
    }

    /// Re-reads every repository, so worktrees and branches made outside Glance show up.
    func reload() {
        repositories = repositories.map { (try? GitRepositoryReader.read($0.url)) ?? $0 }
    }
}
