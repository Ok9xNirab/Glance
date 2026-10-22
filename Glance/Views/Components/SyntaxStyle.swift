//
//  SyntaxStyle.swift
//  Glance
//

import AppKit
import Foundation
import SwiftUI

extension SyntaxToken {
    var color: Color {
        switch self {
        case .plain: Palette.code
        case .keyword: Palette.syntaxKeyword
        case .string: Palette.syntaxString
        case .comment: Palette.syntaxComment
        case .number: Palette.syntaxNumber
        case .type: Palette.syntaxType
        }
    }

    /// Keywords are bold and comments italic, as in the design.
    func font(_ base: NSFont) -> NSFont {
        switch self {
        case .keyword: .monospacedSystemFont(ofSize: base.pointSize, weight: .bold)
        case .comment: NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        default: base
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .keyword: .mono(size, weight: .bold)
        case .comment: .mono(size).italic()
        default: .mono(size)
        }
    }
}

extension SyntaxHighlighter {
    /// Highlights `lines` as one newline-joined string, ready for a text view.
    static func highlight(_ lines: [String], as language: SourceLanguage, font: NSFont) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: lines.joined(separator: "\n"),
            attributes: [.font: font, .foregroundColor: NSColor(Palette.code)]
        )
        var lineStart = 0
        for (line, spans) in zip(lines, spans(for: lines, as: language)) {
            for span in spans {
                let range = NSRange(location: lineStart + span.range.lowerBound, length: span.range.count)
                text.addAttributes([.font: span.token.font(font), .foregroundColor: NSColor(span.token.color)], range: range)
            }
            lineStart += line.utf16.count + 1
        }
        return text
    }
}

extension AttributedString {
    /// One line of code in the mono font at `size`, colored by `spans`.
    init(code: String, spans: [SyntaxSpan], size: CGFloat) {
        self.init(code)
        self.font = Font.mono(size)
        self.foregroundColor = Palette.code
        for span in spans {
            guard
                let lower = Index(String.Index(utf16Offset: span.range.lowerBound, in: code), within: self),
                let upper = Index(String.Index(utf16Offset: span.range.upperBound, in: code), within: self)
            else { continue }
            self[lower..<upper].font = span.token.font(size: size)
            self[lower..<upper].foregroundColor = span.token.color
        }
    }
}
