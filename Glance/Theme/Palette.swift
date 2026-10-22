//
//  Palette.swift
//  Glance
//

import AppKit
import SwiftUI

/// Color tokens from the Glance design, each resolving per light/dark appearance.
enum Palette {
    // Surfaces
    static let window = Color(light: .rgb(0xFFFFFF), dark: .rgb(0x1E1E1F))
    static let sidebar = Color(light: .rgb(0xEBEAED), dark: .rgb(0x29292B))
    static let column = Color(light: .rgb(0xFAFAFA), dark: .rgb(0x232324))
    static let tabBar = Color(light: .rgb(0xF1F1F3), dark: .rgb(0x252526))
    static let switcherPanel = Color(light: .rgba(255, 255, 255, 0.96), dark: .rgba(44, 44, 46, 0.97))
    static let separator = Color(light: .rgba(0, 0, 0, 0.1), dark: .rgba(255, 255, 255, 0.09))

    // Text
    static let text = Color(light: .rgb(0x1D1D1F), dark: .rgb(0xECECEE))
    static let secondaryText = Color(light: .rgb(0x68686D), dark: .rgb(0xA3A3A8))

    // Controls
    static let selection = Color(light: .rgba(0, 0, 0, 0.08), dark: .rgba(255, 255, 255, 0.1))
    static let hover = Color(light: .rgba(0, 0, 0, 0.045), dark: .rgba(255, 255, 255, 0.05))
    static let button = Color(light: .rgb(0xFFFFFF), dark: .rgba(255, 255, 255, 0.1))
    static let buttonBorder = Color(light: .rgba(0, 0, 0, 0.13), dark: .clear)
    static let segment = Color(light: .rgba(0, 0, 0, 0.06), dark: .rgba(255, 255, 255, 0.07))
    static let segmentOn = Color(light: .rgb(0xFFFFFF), dark: .rgba(255, 255, 255, 0.2))
    static let field = Color(light: .rgb(0xFFFFFF), dark: .rgba(255, 255, 255, 0.06))
    static let fieldBorder = Color(light: .rgba(0, 0, 0, 0.15), dark: .rgba(255, 255, 255, 0.09))
    static let keycap = Color(light: .rgba(0, 0, 0, 0.16), dark: .rgba(255, 255, 255, 0.18))

    // Diff
    static let additionBackground = Color(light: .rgba(52, 199, 89, 0.12), dark: .rgba(48, 209, 88, 0.13))
    static let additionGutter = Color(light: .rgba(52, 199, 89, 0.2), dark: .rgba(48, 209, 88, 0.21))
    static let additionText = Color(light: .rgb(0x1B7A33), dark: .rgb(0x5BDB7E))
    static let deletionBackground = Color(light: .rgba(255, 59, 48, 0.09), dark: .rgba(255, 69, 58, 0.14))
    static let deletionGutter = Color(light: .rgba(255, 59, 48, 0.16), dark: .rgba(255, 69, 58, 0.23))
    static let deletionText = Color(light: .rgb(0xC1271D), dark: .rgb(0xFF7A70))
    static let emptyCell = Color(light: .rgb(0xF3F3F5), dark: .rgb(0x19191A))
    static let code = Color(light: .rgb(0x1D1D1F), dark: .rgb(0xE6E6E8))
    static let gutter = Color(light: .rgb(0x68686D), dark: .rgb(0x9C9CA2))

    // Agent activity
    static let agent = Color(light: .rgb(0x8A35C2), dark: .rgb(0xD08CF5))
    static let agentBackground = Color(light: .rgba(175, 82, 222, 0.13), dark: .rgba(191, 90, 242, 0.2))
    static let agentDot = Color(light: .rgb(0xAF52DE), dark: .rgb(0xBF5AF2))

    // Git status badges
    static let modifiedText = Color(light: .rgb(0x9A5600), dark: .rgb(0xFFB340))
    static let modifiedBackground = Color(light: .rgba(255, 149, 0, 0.18), dark: .rgba(255, 159, 10, 0.2))
    static let addedText = Color(light: .rgb(0x1B7A33), dark: .rgb(0x5BDB7E))
    static let addedBackground = Color(light: .rgba(52, 199, 89, 0.18), dark: .rgba(48, 209, 88, 0.2))
    static let deletedText = Color(light: .rgb(0xC1271D), dark: .rgb(0xFF7A70))
    static let deletedBackground = Color(light: .rgba(255, 59, 48, 0.13), dark: .rgba(255, 69, 58, 0.2))

    // Editor
    static let currentLine = Color(light: .rgba(0, 122, 255, 0.07), dark: .rgba(10, 132, 255, 0.12))
    static let addedBar = Color(light: .rgb(0x34C759), dark: .rgb(0x30D158))
    static let modifiedBar = Color(light: .rgb(0xFF9F0A), dark: .rgb(0xFF9F0A))
    static let minimapLine = Color(light: .rgba(0, 0, 0, 0.28), dark: .rgba(255, 255, 255, 0.3))
    static let minimapViewport = Color(light: .rgba(0, 0, 0, 0.06), dark: .rgba(255, 255, 255, 0.07))

    // Syntax
    static let syntaxKeyword = Color(light: .rgb(0x9B2393), dark: .rgb(0xFF7AB2))
    static let syntaxString = Color(light: .rgb(0xC41A16), dark: .rgb(0xFF8170))
    static let syntaxComment = Color(light: .rgb(0x5D6C79), dark: .rgb(0x8D9AA6))
    static let syntaxNumber = Color(light: .rgb(0x1C00CF), dark: .rgb(0xD9C97C))
    static let syntaxType = Color(light: .rgb(0x0B4F79), dark: .rgb(0x6BDFFF))
}

extension FileStatus {
    var foreground: Color {
        switch self {
        case .added: Palette.addedText
        case .modified: Palette.modifiedText
        case .deleted: Palette.deletedText
        }
    }

    var background: Color {
        switch self {
        case .added: Palette.addedBackground
        case .modified: Palette.modifiedBackground
        case .deleted: Palette.deletedBackground
        }
    }
}

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    init(hex: UInt32) {
        self.init(nsColor: .rgb(hex))
    }
}

extension NSColor {
    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static func rgba(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: alpha)
    }
}
