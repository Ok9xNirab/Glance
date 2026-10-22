//
//  WorktreeFileReader.swift
//  Glance
//

import Foundation

/// Lists a worktree's files and reads one for the Files view.
nonisolated enum WorktreeFileReader {
    /// Files larger than this aren't shown, since highlighting them would stall the editor.
    private static let sizeLimit = 1_000_000

    /// Tracked files plus untracked ones that aren't ignored, the files a project's tree is made of.
    static func list(_ worktree: URL) async throws -> Set<String> {
        let output = try await Git.run(
            ["--no-optional-locks", "-c", "core.quotePath=false", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            in: worktree
        )
        // A nested repository is listed as its folder, with a trailing slash.
        return Set(output.split(separator: "\0").lazy.filter { !$0.hasSuffix("/") }.map(String.init))
    }

    /// The file as it is on disk, or for a deleted file as it is in `HEAD`.
    static func read(_ path: String, in worktree: URL, deleted: Bool) async -> LoadedFile {
        let data: Data
        if deleted {
            guard let text = try? await Git.run(["show", "HEAD:\(path)"], in: worktree) else {
                return .unavailable("This file was deleted, and git couldn’t read it from HEAD.")
            }
            data = Data(text.utf8)
        } else {
            let url = worktree.appending(path: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return .unavailable("This file no longer exists.")
            }
            if isDirectory.boolValue { return .unavailable("This is a submodule, so its files aren’t shown here.") }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > sizeLimit {
                return .unavailable("This file is too large to show.")
            }
            do {
                data = try Data(contentsOf: url)
            } catch {
                return .unavailable(error.localizedDescription)
            }
        }
        if data.count > sizeLimit { return .unavailable("This file is too large to show.") }
        if data.contains(0) { return .unavailable("This is a binary file.") }
        guard let text = String(data: data, encoding: .utf8) else { return .unavailable("This file isn’t UTF-8 text.") }
        return .text(FileContent(text))
    }
}
