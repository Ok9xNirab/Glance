//
//  FileStatus.swift
//  Glance
//

import Foundation

enum FileStatus: String {
    case added = "A"
    case modified = "M"
    case deleted = "D"

    var label: String {
        switch self {
        case .added: "Added"
        case .modified: "Modified"
        case .deleted: "Deleted"
        }
    }
}

extension String {
    /// The directory part of a repository-relative path, including the trailing slash.
    var pathDirectory: String {
        guard let slash = lastIndex(of: "/") else { return "" }
        return String(self[...slash])
    }

    /// The last component of a repository-relative path.
    var pathName: String {
        guard let slash = lastIndex(of: "/") else { return self }
        return String(self[index(after: slash)...])
    }
}
