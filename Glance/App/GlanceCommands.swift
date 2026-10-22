//
//  GlanceCommands.swift
//  Glance
//

import SwiftUI

struct GlanceCommands: Commands {
    let model: AppModel

    var body: some Commands {
        // ⌘P is "Go to File…" here, not Print.
        CommandGroup(replacing: .printItem) {}

        CommandGroup(before: .toolbar) {
            Button("Toggle Sidebar", action: model.toggleSidebar)
                .keyboardShortcut("s", modifiers: [.control, .command])
            Divider()
            Button("Changes") { model.mode = .changes }
                .keyboardShortcut("1")
            Button("History") { model.mode = .history }
                .keyboardShortcut("2")
            Button("Files") { model.mode = .files }
                .keyboardShortcut("3")
            Divider()
        }

        CommandMenu("Navigate") {
            Button("Switch Worktree or Branch…") { model.isSwitcherPresented = true }
                .keyboardShortcut("k")
            Button("Go to File…", action: model.goToFile)
                .keyboardShortcut("p")
            Divider()
            Button("Copy for Agent", action: model.copyForAgent)
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }
}
