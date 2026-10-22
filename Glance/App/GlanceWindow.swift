//
//  GlanceWindow.swift
//  Glance
//

import SwiftUI

/// One window, with its own `AppModel`. The scene's value is the worktree it shows, so a restored window reopens it
/// and opening a worktree that's already showing brings its window forward.
struct GlanceWindow: View {
    static let id = "worktree"

    @Binding var worktreePath: String?
    @State private var model: AppModel

    init(library: RepositoryLibrary, worktreePath: Binding<String?>) {
        _worktreePath = worktreePath
        _model = State(initialValue: AppModel(library: library, worktreePath: worktreePath.wrappedValue))
    }

    var body: some View {
        RootView()
            .environment(model)
            .focusedSceneValue(\.appModel, model)
            .navigationTitle(model.windowTitle)
            .frame(minWidth: 1080, minHeight: 640)
            .onChange(of: model.currentWorktreeID, initial: true) {
                if worktreePath != model.currentWorktreeID { worktreePath = model.currentWorktreeID }
            }
    }
}

extension FocusedValues {
    /// The model of the window the menu commands act on.
    @Entry var appModel: AppModel?
}
