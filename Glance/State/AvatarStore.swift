//
//  AvatarStore.swift
//  Glance
//

import AppKit
import CryptoKit
import Foundation
import Observation

/// Fetches the avatars of repository owners from their Git host, and of committers from GitHub or Gravatar, and
/// caches them on disk for a week.
@Observable
final class AvatarStore {
    struct Avatar {
        let image: NSImage
        /// Organizations are drawn as rounded squares and people as circles, as the hosts do.
        let isOrganization: Bool
    }

    private(set) var avatars: [String: Avatar] = [:]
    private(set) var committerAvatars: [String: NSImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    func avatar(host: String, owner: String) -> Avatar? {
        avatars[Self.key(host: host, owner: owner)]
    }

    /// Loads the avatar from the disk cache, or from the host when the cache is missing or stale. Failures are
    /// retried on the next launch rather than within this one.
    func load(host: String, owner: String) async {
        let key = Self.key(host: host, owner: owner)
        guard requested.insert(key).inserted else { return }

        let cached = Self.readCache(key: key)
        if let cached { avatars[key] = cached.avatar }
        guard cached.map({ Date.now.timeIntervalSince($0.date) > Self.maxAge }) ?? true,
              let profile = await AvatarProvider.profile(host: host, owner: owner),
              let (data, _) = try? await URLSession.shared.data(from: profile.avatarURL),
              let image = NSImage(data: data)
        else { return }

        avatars[key] = Avatar(image: image, isOrganization: profile.isOrganization)
        Self.writeCache(key: key, data: data, isOrganization: profile.isOrganization)
    }

    // MARK: Committers

    func committerAvatar(email: String) -> NSImage? {
        committerAvatars[Self.key(email: email)]
    }

    /// Loads the avatar of whoever commits as `email`. Emails without one are remembered for a week too, so they
    /// aren't looked up on every launch.
    func loadCommitter(email: String) async {
        let key = Self.key(email: email)
        guard !email.isEmpty, requested.insert(key).inserted else { return }

        let missFile = Self.cacheDirectory.appending(path: key + ".none")
        if let cached = Self.readCache(key: key) {
            committerAvatars[key] = cached.avatar.image
            guard Date.now.timeIntervalSince(cached.date) > Self.maxAge else { return }
        } else if let date = (try? missFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  Date.now.timeIntervalSince(date) < Self.maxAge {
            return
        }

        guard let url = Self.committerAvatarURL(email: email),
              let (data, response) = try? await URLSession.shared.data(from: url)
        else { return }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else {
            // Gravatar answers 404 for an email it doesn't know.
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
                try? Data().write(to: missFile)
            }
            return
        }
        committerAvatars[key] = image
        Self.writeCache(key: key, data: data, isOrganization: false)
        try? FileManager.default.removeItem(at: missFile)
    }

    /// Keyed by the email's hash, which is also how Gravatar looks it up, so cache file names don't hold emails.
    private static func key(email: String) -> String {
        let digest = SHA256.hash(data: Data(email.trimmingCharacters(in: .whitespaces).lowercased().utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// GitHub's noreply addresses name the account, as `12345+name@` or, for older accounts, `name@`. Any other
    /// email is looked up on Gravatar, which answers 404 rather than a placeholder when it has no image.
    private static func committerAvatarURL(email: String) -> URL? {
        let parts = email.lowercased().split(separator: "@")
        if parts.count == 2, parts[1] == "users.noreply.github.com" {
            if let plus = parts[0].firstIndex(of: "+"), let id = Int(parts[0][..<plus]) {
                return URL(string: "https://avatars.githubusercontent.com/u/\(id)?s=80")
            }
            return URL(string: "https://github.com/\(parts[0]).png?size=80")
        }
        return URL(string: "https://gravatar.com/avatar/\(key(email: email))?s=80&d=404")
    }

    // MARK: Disk cache

    private static func key(host: String, owner: String) -> String {
        "\(host.lowercased())/\(owner.lowercased())"
    }

    private static var cacheDirectory: URL {
        URL.glanceCaches.appending(path: "Avatars", directoryHint: .isDirectory)
    }

    /// Each avatar is stored as `<host>_<owner>.org` or `.user`, so its kind survives without a separate file.
    private static func cacheFiles(key: String) -> (organization: URL, user: URL) {
        let base = key.replacingOccurrences(of: "/", with: "_")
        return (cacheDirectory.appending(path: base + ".org"), cacheDirectory.appending(path: base + ".user"))
    }

    private static func readCache(key: String) -> (avatar: Avatar, date: Date)? {
        let files = cacheFiles(key: key)
        for (file, isOrganization) in [(files.organization, true), (files.user, false)] {
            guard let data = try? Data(contentsOf: file), let image = NSImage(data: data) else { continue }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return (Avatar(image: image, isOrganization: isOrganization), date)
        }
        return nil
    }

    private static func writeCache(key: String, data: Data, isOrganization: Bool) {
        let files = cacheFiles(key: key)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: isOrganization ? files.user : files.organization)
        try? data.write(to: isOrganization ? files.organization : files.user)
    }
}

/// Looks up an owner's avatar URL through their host's public API: GitHub, GitLab, Bitbucket, or Gitea and
/// Forgejo (which covers Codeberg and most self-hosted servers).
private enum AvatarProvider {
    struct Profile {
        let avatarURL: URL
        let isOrganization: Bool
    }

    static func profile(host: String, owner: String) async -> Profile? {
        guard let owner = owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        switch host.lowercased() {
        case "github.com", "ssh.github.com":
            // {"avatar_url": "...", "type": "User" | "Organization"}
            guard let user = await HostAPI.json("https://api.github.com/users/\(owner)") else { return nil }
            return profile(user["avatar_url"], isOrganization: user["type"] as? String == "Organization")
        case "bitbucket.org":
            // Workspaces own Bitbucket repositories: {"links": {"avatar": {"href": "..."}}}
            let workspace = await HostAPI.json("https://api.bitbucket.org/2.0/workspaces/\(owner)")
            let links = workspace?["links"] as? [String: Any]
            return profile((links?["avatar"] as? [String: Any])?["href"], isOrganization: true)
        case let host where host.contains("gitlab"):
            if let group = await HostAPI.json("https://\(host)/api/v4/groups/\(owner)") {
                return profile(group["avatar_url"], isOrganization: true)
            }
            let users = await HostAPI.jsonArray("https://\(host)/api/v4/users?username=\(owner)")
            return profile(users?.first?["avatar_url"], isOrganization: false)
        default:
            if let organization = await HostAPI.json("https://\(host)/api/v1/orgs/\(owner)") {
                return profile(organization["avatar_url"], isOrganization: true)
            }
            let user = await HostAPI.json("https://\(host)/api/v1/users/\(owner)")
            return profile(user?["avatar_url"], isOrganization: false)
        }
    }

    private static func profile(_ avatarURL: Any?, isOrganization: Bool) -> Profile? {
        guard let string = avatarURL as? String, let url = URL(string: string) else { return nil }
        return Profile(avatarURL: url, isOrganization: isOrganization)
    }
}
