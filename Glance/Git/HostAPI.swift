//
//  HostAPI.swift
//  Glance
//

import Foundation

/// Unauthenticated JSON requests to the public APIs of Git hosts.
enum HostAPI {
    enum Response {
        case found(Any)
        /// The host answered 401, 403 or 404: the resource is private, or doesn't exist.
        case inaccessible
    }

    /// `nil` when the request failed or the host answered with any other status.
    static func get(_ string: String) async -> Response? {
        guard let url = URL(string: string),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return nil }
        if [401, 403, 404].contains(status) { return .inaccessible }
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return .found(json)
    }

    static func json(_ string: String) async -> [String: Any]? {
        guard case let .found(json) = await get(string) else { return nil }
        return json as? [String: Any]
    }

    static func jsonArray(_ string: String) async -> [[String: Any]]? {
        guard case let .found(json) = await get(string) else { return nil }
        return json as? [[String: Any]]
    }
}
