//
//  RootView.swift
//  Glance
//

import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            if model.isSidebarVisible {
                SidebarView()
                    .transition(.move(edge: .leading))
            }
            if model.repositories.isEmpty {
                VStack(spacing: 12) {
                    Text("No repositories yet")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Add a folder that contains a Git repository to review its worktrees.")
                        .foregroundStyle(Palette.secondaryText)
                    Button("Add Repository…", action: model.addRepository)
                        .buttonStyle(BezelButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch model.mode {
                case .changes:
                    ChangesScreen(changes: model.changes)
                case .history:
                    HistoryScreen(history: model.history)
                case .files:
                    FilesScreen(files: model.files)
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Palette.text)
        .background(Palette.window)
        .overlay {
            if model.isSwitcherPresented {
                WorktreeSwitcher()
            } else if model.isRepositoryPickerPresented {
                RepositoryPicker()
            }
        }
        .ignoresSafeArea()
        .modifier(KeyboardShortcutMonitor(model: model))
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding { model.alert != nil } set: { if !$0 { model.alert = nil } },
            actions: {},
            message: { Text(model.alert?.message ?? "") }
        )
        .task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                model.reloadRepositories()
                model.changes.refresh()
                model.history.refresh()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel(library: RepositoryLibrary()))
        .frame(width: 1440, height: 900)
}
