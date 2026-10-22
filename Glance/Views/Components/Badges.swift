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

/// A committer's avatar from GitHub or Gravatar. Until it loads, and when there's none, it's a colored circle with
/// their initial.
struct Avatar: View {
    let author: Author
    var size: CGFloat = 16
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let image = model.avatars.committerAvatar(email: author.email) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(Circle())
            } else {
                Text(author.initial)
                    .font(.system(size: size * 0.56, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(author.color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: author.email) { await model.avatars.loadCommitter(email: author.email) }
    }
}

/// The avatar of a repository's owner from its Git host. Until it loads, and for local-only repositories, it's a
/// colored rounded square with the owner's initial (or the repository's).
struct OwnerAvatar: View {
    let repository: Repository
    var size: CGFloat = 18
    var cornerRadius: CGFloat = 5
    @Environment(AppModel.self) private var model

    var body: some View {
        content
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: repository.owner) {
                if let host = repository.host, let owner = repository.owner {
                    await model.avatars.load(host: host, owner: owner)
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let host = repository.host, let owner = repository.owner, let avatar = model.avatars.avatar(host: host, owner: owner) {
            let image = Image(nsImage: avatar.image).resizable().interpolation(.high)
            if avatar.isOrganization {
                image.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                image.clipShape(Circle())
            }
        } else {
            let name = repository.owner ?? repository.name
            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: cornerRadius).fill(color(for: repository.owner)))
        }
    }

    /// The same owner always gets the same color. `String.hashValue` changes between launches, so sum the scalars.
    private func color(for owner: String?) -> Color {
        guard let owner else { return Palette.fileGray }
        let sum = owner.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Palette.owners[sum % Palette.owners.count]
    }
}

/// The fork glyph from the design: two tines joining into one stem. SF Symbols has no fork.
struct ForkIcon: View {
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvasSize in
            // Drawn on the design's 24×24 grid.
            let scale = canvasSize.width / 24
            var path = Path()
            for center in [CGPoint(x: 6, y: 5), CGPoint(x: 18, y: 5), CGPoint(x: 12, y: 19)] {
                path.addEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
            }
            path.move(to: CGPoint(x: 6, y: 7))
            path.addLine(to: CGPoint(x: 6, y: 9))
            path.addQuadCurve(to: CGPoint(x: 9, y: 12), control: CGPoint(x: 6, y: 12))
            path.addLine(to: CGPoint(x: 15, y: 12))
            path.addQuadCurve(to: CGPoint(x: 18, y: 9), control: CGPoint(x: 18, y: 12))
            path.addLine(to: CGPoint(x: 18, y: 7))
            path.move(to: CGPoint(x: 12, y: 12))
            path.addLine(to: CGPoint(x: 12, y: 17))
            context.stroke(
                path.applying(CGAffineTransform(scaleX: scale, y: scale)),
                with: .foreground,
                style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: size, height: size)
    }
}
