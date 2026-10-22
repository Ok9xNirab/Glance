//
//  Appearance.swift
//  Glance
//

import AppKit
import SwiftUI

extension EnvironmentValues {
    /// The accent color chosen in System Settings.
    @Entry var glanceAccent: Color = Color(nsColor: .controlAccentColor)
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
