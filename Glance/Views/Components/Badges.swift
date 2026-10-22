//
//  Badges.swift
//  Glance
//

import SwiftUI

/// The A / M / D git status square. `inverted` is for rows drawn on the accent color.
struct StatusBadge: View {
    let status: FileStatus
    var size: CGFloat = 16
    var inverted = false

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(inverted ? .white : status.foreground)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(inverted ? Color.white.opacity(0.24) : status.background)
            )
            .help(status.label)
    }
}

struct CountBadge: View {
    let count: Int
    var height: CGFloat = 17

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: height)
            .background(Capsule().fill(Palette.selection))
    }
}

struct KeyCap: View {
    let key: String
    var inverted = false

    init(_ key: String, inverted: Bool = false) {
        self.key = key
        self.inverted = inverted
    }

    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 5)
            .frame(height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(inverted ? Color.white.opacity(0.5) : Palette.keycap)
            )
    }
}

/// Keycaps followed by what they do, for status bars.
struct ShortcutHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { KeyCap($0) }
            Text(label)
        }
    }
}

struct LineStats: View {
    let additions: Int
    let deletions: Int
    var inverted = false

    var body: some View {
        HStack(spacing: 5) {
            Text("+\(additions)")
                .foregroundStyle(inverted ? Color.white.opacity(0.82) : Palette.additionText)
            Text("−\(deletions)")
                .foregroundStyle(inverted ? Color.white.opacity(0.82) : Palette.deletionText)
        }
        .font(.mono(11, weight: .medium))
        .fixedSize()
    }
}

/// Purple dot that pulses while an agent is writing.
struct AgentDot: View {
    var color = Palette.agentDot
    @State private var isDimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(isDimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
            .accessibilityLabel("Agent is writing")
    }
}

/// The purple "agent" label on commits.
struct AgentChip: View {
    let title: String
    var inverted = false

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(inverted ? .white : Palette.agent)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(inverted ? Color.white.opacity(0.22) : Palette.agentBackground)
            )
            .fixedSize()
    }
}

struct TagChip: View {
    let title: String
    var inverted = false

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(inverted ? .white : Palette.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(inverted ? Color.white.opacity(0.4) : Palette.separator)
            )
            .fixedSize()
    }
}

struct Avatar: View {
    let author: Author
    var size: CGFloat = 16

    var body: some View {
        Text(author.initial)
            .font(.system(size: size * 0.56, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(author.color))
            .accessibilityHidden(true)
    }
}
