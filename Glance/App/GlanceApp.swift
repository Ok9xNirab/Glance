//
//  GlanceApp.swift
//  Glance
//
//  Created by Istiaq Nirab on 22/10/26.
//

import SwiftUI

@main
struct GlanceApp: App {
    @State private var library = RepositoryLibrary()

    var body: some Scene {
        WindowGroup(id: GlanceWindow.id, for: String.self) { $worktreePath in
            GlanceWindow(library: library, worktreePath: $worktreePath)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            GlanceCommands()
        }
    }
}
