//
//  SyntaxHighlighter.swift
//  Glance
//

import Foundation
import SwiftUI

enum SourceLanguage: String {
    case typeScript = "TypeScript"
    case javaScript = "JavaScript"
    case json = "JSON"
    case markdown = "Markdown"
    case yaml = "YAML"
    case properties = "Properties"
    case plainText = "Plain Text"

    init(path: String) {
        switch path.split(separator: ".").last {
        case "ts": self = .typeScript
        case "js": self = .javaScript
        case "json": self = .json
        case "md": self = .markdown
        case "yml", "yaml": self = .yaml
        case "example", "env": self = .properties
        default: self = .plainText
        }
    }
}

/// A small line-based highlighter, enough to make the sample sources read like an editor.
enum SyntaxHighlighter {
    private enum Token {
        case plain, keyword, string, comment, number, type
    }

    private static let keywords: Set<String> = [
        "import", "from", "export", "const", "let", "var", "function", "return", "if", "else", "async", "await",
        "new", "type", "typeof", "keyof", "of", "in", "for", "while", "class", "extends", "true", "false", "null",
        "undefined", "default", "interface", "as", "throw",
    ]

    // Groups: 1 line comment, 2 string, 3 number, 4 identifier.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(//.*$)|('(?:\\.|[^'])*'|"(?:\\.|[^"])*"|`(?:\\.|[^`])*`)|(\b\d[\d_]*(?:\.\d+)?\b)|([A-Za-z_$][\w$]*)"#
    )

    static func highlight(_ line: String, as language: SourceLanguage) -> AttributedString {
        tokenize(line, as: language).reduce(into: AttributedString()) { result, piece in
            result += styled(piece.text, piece.token)
        }
    }

    private static func tokenize(_ line: String, as language: SourceLanguage) -> [(text: String, token: Token)] {
        switch language {
        case .markdown:
            if line.hasPrefix("#") { return [(line, .keyword)] }
            if line.hasPrefix("```") { return [(line, .comment)] }
            return [(line, .plain)]
        case .properties:
            if line.hasPrefix("#") { return [(line, .comment)] }
            guard let equals = line.firstIndex(of: "="), equals != line.startIndex else { return [(line, .plain)] }
            return [
                (String(line[..<equals]), .type),
                ("=", .plain),
                (String(line[line.index(after: equals)...]), .string),
            ]
        default:
            return tokenizeCode(line, isJSON: language == .json)
        }
    }

    private static func tokenizeCode(_ line: String, isJSON: Bool) -> [(text: String, token: Token)] {
        let source = line as NSString
        var pieces: [(String, Token)] = []
        var last = 0

        for match in pattern.matches(in: line, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > last {
                pieces.append((source.substring(with: NSRange(location: last, length: match.range.location - last)), .plain))
            }
            let text = source.substring(with: match.range)
            let end = match.range.location + match.range.length
            let token: Token
            if match.range(at: 1).location != NSNotFound {
                token = .comment
            } else if match.range(at: 2).location != NSNotFound {
                // In JSON, a string followed by a colon is a key.
                let rest = source.substring(from: end).trimmingCharacters(in: .whitespaces)
                token = isJSON && rest.hasPrefix(":") ? .type : .string
            } else if match.range(at: 3).location != NSNotFound {
                token = .number
            } else if keywords.contains(text) {
                token = .keyword
            } else {
                token = text.first?.isUppercase == true ? .type : .plain
            }
            pieces.append((text, token))
            last = end
        }
        if last < source.length {
            pieces.append((source.substring(from: last), .plain))
        }
        return pieces
    }

    private static func styled(_ text: String, _ token: Token) -> AttributedString {
        var piece = AttributedString(text)
        switch token {
        case .plain:
            break
        case .keyword:
            piece.foregroundColor = Palette.syntaxKeyword
            piece.inlinePresentationIntent = .stronglyEmphasized
        case .string:
            piece.foregroundColor = Palette.syntaxString
        case .comment:
            piece.foregroundColor = Palette.syntaxComment
            piece.inlinePresentationIntent = .emphasized
        case .number:
            piece.foregroundColor = Palette.syntaxNumber
        case .type:
            piece.foregroundColor = Palette.syntaxType
        }
        return piece
    }
}
