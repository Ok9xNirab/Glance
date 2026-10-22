//
//  RootView.swift
//  Glance
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            if model.isSidebarVisible {
                SidebarView()
                    .transition(.move(edge: .leading))
            }
            switch model.mode {
            case .changes:
                ChangesScreen(changes: model.changes)
            case .history:
                HistoryScreen(history: model.history)
            case .files:
                FilesScreen(files: model.files)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Palette.text)
        .background(Palette.window)
        .overlay {
            if model.isSwitcherPresented {
                WorktreeSwitcher()
            }
        }
        .ignoresSafeArea()
        .modifier(KeyboardShortcutMonitor(model: model))
    }
}

#Preview {
    RootView()
        .environment(AppModel())
        .frame(width: 1440, height: 900)
}
