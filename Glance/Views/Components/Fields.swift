//
//  Fields.swift
//  Glance
//

import SwiftUI

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var shortcut: String?
    var isFocused: FocusState<Bool>.Binding?

    init(_ placeholder: String, text: Binding<String>, shortcut: String? = nil, isFocused: FocusState<Bool>.Binding? = nil) {
        self.placeholder = placeholder
        _text = text
        self.shortcut = shortcut
        self.isFocused = isFocused
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
            field
            if let shortcut, text.isEmpty {
                KeyCap(shortcut).foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .fieldBox()
    }

    @ViewBuilder private var field: some View {
        let textField = TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.secondaryText))
            .textFieldStyle(.plain)
        if let isFocused {
            textField.focused(isFocused)
        } else {
            textField
        }
    }
}

private extension View {
    func fieldBox() -> some View {
        background(RoundedRectangle(cornerRadius: 6).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.fieldBorder, lineWidth: 1))
    }
}
