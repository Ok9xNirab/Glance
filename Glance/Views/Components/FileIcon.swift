//
//  FileIcon.swift
//  Glance
//

import SwiftUI

/// A file's type icon: a symbol or a short language label, colored by type.
/// `inverted` is for rows drawn on the accent color.
struct FileIcon: View {
    let name: String
    var size: CGFloat = 12
    var inverted = false

    var body: some View {
        let kind = FileKind(name: name)
        Group {
            switch kind.glyph {
            case let .symbol(symbol):
                Image(systemName: symbol)
                    .font(.system(size: size))
            case let .label(label):
                Text(label)
                    .font(.system(size: size * (label.count > 2 ? 0.58 : 0.72), weight: .heavy, design: .rounded))
                    .tracking(-0.3)
                    .fixedSize()
            }
        }
        .foregroundStyle(inverted ? .white.opacity(0.9) : kind.color)
        .frame(width: size + 4, height: size + 4)
        .accessibilityHidden(true)
    }
}

/// Picks a file's icon from its name: well-known files first, then the extension.
struct FileKind {
    enum Glyph {
        case symbol(String)
        case label(String)
    }

    let glyph: Glyph
    let color: Color

    init(name: String) {
        let lowered = name.lowercased()
        switch lowered {
        case "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock":
            self.init(.symbol("shippingbox.fill"), Palette.fileRed)
            return
        case "tsconfig.json", "jsconfig.json":
            self.init(.symbol("gearshape.fill"), Palette.fileBlue)
            return
        case "package.swift":
            self.init(.symbol("shippingbox.fill"), Palette.fileOrange)
            return
        case "dockerfile", "docker-compose.yml", "docker-compose.yaml":
            self.init(.symbol("cube.fill"), Palette.fileBlue)
            return
        case "license", "license.md", "license.txt":
            self.init(.symbol("checkmark.seal.fill"), Palette.fileYellow)
            return
        case "makefile":
            self.init(.symbol("hammer.fill"), Palette.fileOrange)
            return
        default:
            break
        }
        if lowered.hasPrefix("readme") {
            self.init(.symbol("info.circle.fill"), Palette.fileBlue)
            return
        }
        if lowered.hasPrefix(".git") {
            self.init(.symbol("arrow.triangle.branch"), Palette.fileOrange)
            return
        }
        if lowered.hasPrefix(".env") {
            self.init(.symbol("key.fill"), Palette.fileYellow)
            return
        }
        if lowered.contains(".config.") || (lowered.hasPrefix(".") && lowered.hasSuffix("rc")) {
            self.init(.symbol("gearshape.fill"), Palette.fileGray)
            return
        }

        let ext = lowered.contains(".") ? lowered.split(separator: ".").last ?? "" : ""
        switch ext {
        case "ts", "mts", "cts": self.init(.label("TS"), Palette.fileBlue)
        case "tsx", "jsx": self.init(.symbol("atom"), Palette.fileCyan)
        case "js", "mjs", "cjs": self.init(.label("JS"), Palette.fileYellow)
        case "json": self.init(.symbol("curlybraces"), Palette.fileYellow)
        case "swift": self.init(.symbol("swift"), Palette.fileOrange)
        case "php": self.init(.label("PHP"), Palette.filePurple)
        case "py": self.init(.label("PY"), Palette.fileBlue)
        case "rb": self.init(.label("RB"), Palette.fileRed)
        case "go": self.init(.label("GO"), Palette.fileCyan)
        case "rs": self.init(.label("RS"), Palette.fileOrange)
        case "java": self.init(.symbol("cup.and.saucer.fill"), Palette.fileRed)
        case "kt", "kts": self.init(.label("KT"), Palette.filePurple)
        case "c", "h": self.init(.label("C"), Palette.fileBlue)
        case "cpp", "cc", "hpp": self.init(.label("C++"), Palette.fileBlue)
        case "cs": self.init(.label("C#"), Palette.filePurple)
        case "html", "htm", "vue", "svelte": self.init(.symbol("chevron.left.forwardslash.chevron.right"), Palette.fileOrange)
        case "css", "scss", "sass", "less": self.init(.symbol("number"), Palette.filePurple)
        case "md", "mdx", "markdown": self.init(.symbol("text.alignleft"), Palette.fileBlue)
        case "yml", "yaml", "toml", "ini", "xml", "plist": self.init(.symbol("list.bullet.indent"), Palette.filePurple)
        case "sh", "bash", "zsh", "fish": self.init(.symbol("terminal.fill"), Palette.fileGreen)
        case "sql", "prisma": self.init(.symbol("cylinder.split.1x2.fill"), Palette.fileYellow)
        case "png", "jpg", "jpeg", "gif", "webp", "ico", "heic": self.init(.symbol("photo.fill"), Palette.filePurple)
        case "svg": self.init(.symbol("scribble"), Palette.fileOrange)
        case "lock": self.init(.symbol("lock.fill"), Palette.fileGray)
        case "txt", "log": self.init(.symbol("doc.text"), Palette.fileGray)
        default: self.init(.symbol("doc"), Palette.fileGray)
        }
    }

    private init(_ glyph: Glyph, _ color: Color) {
        self.glyph = glyph
        self.color = color
    }
}
