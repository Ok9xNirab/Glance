//
//  GlanceCommands.swift
//  Glance
//

import SwiftUI

/// Menu commands, which act on the focused window.
struct GlanceCommands: Commands {
    @FocusedValue(\.appModel) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // ⌘P is "Go to File…" here, not Print.
        CommandGroup(replacing: .printItem) {}

        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: GlanceWindow.id) }
                .keyboardShortcut("n")
            Button("Add Repository…") { model?.addRepository() }
                .keyboardShortcut("o")
                .disabled(model == nil)
        }

        CommandGroup(before: .toolbar) {
            Group {
                Button("Toggle Sidebar") { model?.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.control, .command])
                Divider()
                Button("Changes") { model?.mode = .changes }
                    .keyboardShortcut("1")
                Button("History") { model?.mode = .history }
                    .keyboardShortcut("2")
                Button("Files") { model?.mode = .files }
                    .keyboardShortcut("3")
                Divider()
            }
            .disabled(model == nil)
        }

        CommandMenu("Navigate") {
            Group {
                Button("Switch Worktree or Branch…") {
                    model?.isRepositoryPickerPresented = false
                    model?.isSwitcherPresented = true
                }
                .keyboardShortcut("k")
                Button("Switch Repository…") {
                    model?.isSwitcherPresented = false
                    model?.isRepositoryPickerPresented = true
                }
                .keyboardShortcut("t")
                Button("Go to File…") { model?.goToFile() }
                    .keyboardShortcut("p")
                Divider()
                Button("Copy for Agent") { model?.copyForAgent() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .disabled(model == nil)
        }
    }
}
