//
//  FileWatcher.swift
//  Glance
//

import CoreServices
import Foundation

/// Calls `onChange` on the main queue when files in a worktree change, ignoring git's own bookkeeping and the nested
/// `.worktrees/` folder, whose worktrees have watchers of their own.
final class FileWatcher {
    private let root: String
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?

    init(_ url: URL, onChange: @escaping () -> Void) {
        root = url.standardizedFileURL.path
        self.onChange = onChange

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            MainActor.assumeIsolated {
                Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().handle(paths.prefix(count))
            }
        }
        // Events arrive at most every half second, so a burst of writes reads the worktree once.
        stream = FSEventStreamCreate(
            nil, callback, &context, [root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func handle(_ paths: ArraySlice<String>) {
        if paths.contains(where: isRelevant) { onChange() }
    }

    private func isRelevant(_ path: String) -> Bool {
        let relative = path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
        if relative.hasPrefix(".worktrees/") { return false }
        // Inside `.git`, only staging and switching branches change what's uncommitted.
        if relative.hasPrefix(".git/") { return relative == ".git/index" || relative == ".git/HEAD" }
        return true
    }
}
