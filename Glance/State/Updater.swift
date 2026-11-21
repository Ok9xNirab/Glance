//
//  Updater.swift
//  Glance
//

import Combine
import Observation
import Sparkle
import SwiftUI

/// Sparkle's updater. The feed (`SUFeedURL`) and its public key (`SUPublicEDKey`) are in `Info.plist`; the appcast is
/// `docs/appcast.xml` on the landing page, written by `scripts/make-dmg.sh`.
@Observable
final class Updater {
    static let shared = Updater()

    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: AnyCancellable?

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// Glance › Check for Updates…
struct CheckForUpdatesCommand: View {
    private let updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
