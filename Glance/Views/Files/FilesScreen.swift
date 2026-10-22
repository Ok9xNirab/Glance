//
//  FilesScreen.swift
//  Glance
//

import SwiftUI

/// Browse the whole project, with uncommitted changes marked in the tree and the editor gutter.
struct FilesScreen: View {
    let files: FilesModel

    var body: some View {
        HStack(spacing: 0) {
            FilesColumn(files: files)
            FileEditor(files: files)
        }
    }
}

#Preview {
    let model = AppModel(library: RepositoryLibrary())
    FilesScreen(files: model.files)
        .environment(model)
        .frame(width: 1220, height: 900)
}
