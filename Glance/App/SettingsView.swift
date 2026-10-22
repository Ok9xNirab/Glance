//
//  SettingsView.swift
//  Glance
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppearanceSetting.storageKey) private var appearance = AppearanceSetting.system
    @AppStorage(AccentChoice.storageKey) private var accent = AccentChoice.blue

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Accent color", selection: $accent) {
                ForEach(AccentChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }

            HStack(spacing: 8) {
                ForEach(AccentChoice.allCases) { choice in
                    Circle()
                        .fill(choice.color)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.white, lineWidth: choice == accent ? 2 : 0))
                        .onTapGesture { accent = choice }
                        .accessibilityLabel(choice.title)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}

#Preview {
    SettingsView()
}
