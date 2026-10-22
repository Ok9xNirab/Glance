//
//  Git.swift
//  Glance
//

import Foundation

/// Runs the `git` command line tool, the same one Terminal uses, so the user's config, hooks and credentials apply.
enum Git {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Runs `git <arguments>` in `directory` and returns its standard output. Throws git's error message when it
    /// exits with a failure.
    @discardableResult
    nonisolated static func run(_ arguments: [String], in directory: URL) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/git")
            process.arguments = arguments
            process.currentDirectoryURL = directory
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            process.standardInput = FileHandle.nullDevice

            try process.run()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                // "fatal: a branch named 'x' already exists" reads better without the prefix.
                let message = String(decoding: errorData, as: UTF8.self)
                    .split(separator: "\n")
                    .map { line in ["fatal: ", "error: "].reduce(String(line)) { $0.hasPrefix($1) ? String($0.dropFirst($1.count)) : $0 } }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw Failure(message: message.isEmpty ? "git \(arguments.first ?? "") failed." : message)
            }
            return String(decoding: outputData, as: UTF8.self)
        }.value
    }
}
