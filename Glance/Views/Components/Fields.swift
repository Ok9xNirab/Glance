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

struct BoxedTextField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.secondaryText))
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .fieldBox()
    }
}

struct BoxedTextEditor: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 3)
            .padding(.vertical, 5)
            .frame(height: 60)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .allowsHitTesting(false)
                }
            }
            .fieldBox()
            .accessibilityLabel(placeholder)
    }
}

private extension View {
    func fieldBox() -> some View {
        background(RoundedRectangle(cornerRadius: 6).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.fieldBorder, lineWidth: 1))
    }
}
