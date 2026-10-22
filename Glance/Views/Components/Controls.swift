//
//  Controls.swift
//  Glance
//

import SwiftUI

/// A borderless 28pt toolbar button that highlights on hover.
struct IconButton: View {
    let systemImage: String
    let help: String
    var size: CGFloat = 28
    var tint: Color?
    let action: () -> Void

    init(_ systemImage: String, help: String, size: CGFloat = 28, tint: Color? = nil, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.help = help
        self.size = size
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size > 24 ? 14 : 11))
                .foregroundStyle(tint ?? Palette.secondaryText)
                .frame(width: size, height: size)
        }
        .buttonStyle(RowButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Rounded hover highlight for list rows and borderless buttons; `fill` marks the selected state.
struct RowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 6
    var fill: Color?

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, cornerRadius: cornerRadius, fill: fill)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let fill: Color?
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(fill ?? (isHovered ? Palette.hover : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .onHover { isHovered = $0 }
        }
    }
}

/// The small white push button used for hunk actions and the switcher.
struct BezelButtonStyle: ButtonStyle {
    var height: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 9)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.button)
                    .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.5)
            )
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.buttonBorder, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The segmented control from the design, which can carry a count badge on a segment.
struct PillPicker<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        var badge: Int?

        init(_ value: Value, _ title: String, badge: Int? = nil) {
            self.value = value
            self.title = title
            self.badge = badge
        }
    }

    @Binding var selection: Value
    let items: [Item]
    var fillsWidth = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.value) { item in
                let isSelected = item.value == selection
                Button {
                    selection = item.value
                } label: {
                    HStack(spacing: 6) {
                        Text(item.title).fontWeight(.medium)
                        if let badge = item.badge {
                            CountBadge(count: badge, height: 15)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
                    .frame(height: 22)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Palette.segmentOn)
                                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.segment))
    }
}

/// Copies to the pasteboard and briefly confirms with "Copied".
struct CopyForAgentButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let copied = model.recentlyCopied == .agentContext
        Button(action: model.copyForAgent) {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13))
                    .frame(width: 15)
                Text(copied ? "Copied" : "Copy for Agent")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
        }
        .buttonStyle(RowButtonStyle())
        .help("Copy path and diff as a fenced block for your agent (⌘⇧C)")
    }
}
