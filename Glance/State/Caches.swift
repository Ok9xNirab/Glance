//
//  Caches.swift
//  Glance
//

import Foundation

extension URL {
    /// Glance's own folder in `~/Library/Caches`, which outside the App Sandbox is shared by every app.
    static var glanceCaches: URL {
        cachesDirectory.appending(path: Bundle.main.bundleIdentifier ?? "Glance", directoryHint: .isDirectory)
    }
}
