//
//  ChangesScreen.swift
//  Glance
//

import SwiftUI

/// Review the agent's uncommitted diff, file by file, then commit.
struct ChangesScreen: View {
    let changes: ChangesModel

    var body: some View {
        HStack(spacing: 0) {
            ChangesColumn(changes: changes)
            ChangesDetail(changes: changes)
        }
    }
}

#Preview {
    let model = AppModel()
    ChangesScreen(changes: model.changes)
        .environment(model)
        .frame(width: 1220, height: 900)
}
