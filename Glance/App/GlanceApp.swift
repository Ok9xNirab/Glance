//
//  GlanceApp.swift
//  Glance
//
//  Created by Istiaq Nirab on 22/10/26.
//

import SwiftUI

@main
struct GlanceApp: App {
    @State private var model = AppModel()
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system
    @AppStorage(AccentChoice.storageKey) private var accent = AccentChoice.blue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.glanceAccent, accent.color)
                .tint(accent.color)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 1080, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            GlanceCommands(model: model)
        }

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
