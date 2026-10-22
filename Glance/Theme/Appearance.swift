//
//  Appearance.swift
//  Glance
//

import SwiftUI

/// The accent colors offered by the design.
enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, pink, orange

    static let storageKey = "accent"

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: Color(hex: 0x007AFF)
        case .purple: Color(hex: 0xA550A7)
        case .pink: Color(hex: 0xF74F9E)
        case .orange: Color(hex: 0xFF7F0F)
        }
    }
}

enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension EnvironmentValues {
    @Entry var glanceAccent: Color = AccentChoice.blue.color
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
