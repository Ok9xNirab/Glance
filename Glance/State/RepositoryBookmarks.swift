//
//  RepositoryBookmarks.swift
//  Glance
//

import Foundation

/// Remembers the folders added to the sidebar as bookmarks, which keep finding them even after they are moved, and opens them again on
/// the next launch.
enum RepositoryBookmarks {
    private static let defaultsKey = "repositoryBookmarks"

    static func save(_ urls: [URL]) {
        let bookmarks = urls.compactMap { try? $0.bookmarkData(options: .withSecurityScope) }
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    /// Resolves the saved bookmarks and starts accessing each folder for the rest of the session.
    static func restore() -> [URL] {
        let bookmarks = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
        var isAnyStale = false
        let urls = bookmarks.compactMap { bookmark -> URL? in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
                  url.startAccessingSecurityScopedResource()
            else { return nil }
            isAnyStale = isAnyStale || isStale
            return url
        }
        if isAnyStale { save(urls) }
        return urls
    }
}
