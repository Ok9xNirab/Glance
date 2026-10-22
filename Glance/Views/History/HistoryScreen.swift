//
//  HistoryScreen.swift
//  Glance
//

import SwiftUI

struct HistoryScreen: View {
    let history: HistoryModel

    var body: some View {
        HStack(spacing: 0) {
            HistoryColumn(history: history)
            CommitDetail(history: history)
        }
    }
}

#Preview {
    let model = AppModel()
    HistoryScreen(history: model.history)
        .environment(model)
        .frame(width: 1220, height: 900)
}
