//
//  SyntaxHighlighter.swift
//  Glance
//

import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterJSON
import TreeSitterJavaScript
import TreeSitterMarkdown
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

enum SourceLanguage: String {
    case typeScript = "TypeScript"
    case tsx = "TSX"
    case javaScript = "JavaScript"
    case json = "JSON"
    case markdown = "Markdown"
    case yaml = "YAML"
    case properties = "Properties"
    case shell = "Shell"
    case swift = "Swift"
    case plainText = "Plain Text"

    init(path: String) {
        switch path.split(separator: ".").last {
        case "ts", "mts", "cts": self = .typeScript
        case "tsx": self = .tsx
        case "js", "mjs", "cjs", "jsx": self = .javaScript
        case "json": self = .json
        case "md": self = .markdown
        case "yml", "yaml": self = .yaml
        case "example", "env": self = .properties
        case "sh", "bash", "zsh": self = .shell
        case "swift": self = .swift
        default: self = .plainText
        }
    }

    /// Data formats color their keys, where code leaves property names plain.
    fileprivate var colorsKeys: Bool {
        self == .json || self == .yaml || self == .properties
    }
}

enum SyntaxToken {
    case plain, keyword, string, comment, number, type
}

/// A colored run within one line, in UTF-16 offsets from the line's start.
struct SyntaxSpan {
    let range: Range<Int>
    let token: SyntaxToken
}

/// Highlights source with tree-sitter grammars, mapping their captures onto the design's few syntax colors.
enum SyntaxHighlighter {
    private struct Grammar {
        let language: Language
        let query: Query
        /// Most grammars list general patterns first and refine them later; JSON puts the specific ones first.
        let laterPatternsWin: Bool
    }

    private static var grammars: [SourceLanguage: Grammar?] = [:]

    /// The spans of each line in `lines`, parsed as one document so strings and comments can span lines.
    static func spans(for lines: [String], as language: SourceLanguage) -> [[SyntaxSpan]] {
        let unstyled = lines.map { _ in [SyntaxSpan]() }
        let source = lines.joined(separator: "\n")
        guard let grammar = grammar(for: language) else { return unstyled }
        let parser = Parser()
        guard (try? parser.setLanguage(grammar.language)) != nil, let tree = parser.parse(source) else { return unstyled }

        var captures: [(range: NSRange, pattern: Int, token: SyntaxToken)] = []
        for match in grammar.query.execute(in: tree).resolve(with: .init(string: source)) {
            for capture in match.captures {
                guard let name = capture.name, let token = token(for: name, in: language) else { continue }
                captures.append((capture.range, capture.patternIndex, token))
            }
        }
        // Paint wide captures first so the narrower ones nested inside them win; on the same range, pattern order decides.
        captures.sort { a, b in
            if a.range.length != b.range.length { return a.range.length > b.range.length }
            return grammar.laterPatternsWin ? a.pattern < b.pattern : a.pattern > b.pattern
        }
        var paint = [SyntaxToken](repeating: .plain, count: source.utf16.count)
        for capture in captures {
            let bounds = max(capture.range.location, 0)..<min(NSMaxRange(capture.range), paint.count)
            guard !bounds.isEmpty else { continue }
            paint.replaceSubrange(bounds, with: repeatElement(capture.token, count: bounds.count))
        }

        var result: [[SyntaxSpan]] = []
        var lineStart = 0
        for line in lines {
            let lineEnd = lineStart + line.utf16.count
            var spans: [SyntaxSpan] = []
            var runStart = lineStart
            while runStart < lineEnd {
                var runEnd = runStart + 1
                while runEnd < lineEnd, paint[runEnd] == paint[runStart] { runEnd += 1 }
                if paint[runStart] != .plain {
                    spans.append(SyntaxSpan(range: (runStart - lineStart)..<(runEnd - lineStart), token: paint[runStart]))
                }
                runStart = runEnd
            }
            result.append(spans)
            lineStart = lineEnd + 1
        }
        return result
    }

    /// The color for a capture name, `.plain` to reset its range, or `nil` to leave it as the enclosing capture painted it.
    private static func token(for capture: String, in language: SourceLanguage) -> SyntaxToken? {
        switch capture {
        case "string.special.key", "text.uri", "text.reference": return .type
        case "text.title": return .keyword
        case "text.literal": return .comment
        case "none", "embedded": return .plain
        case "constant.builtin": return .keyword
        case "punctuation.special" where language == .markdown: return .keyword
        default: break
        }
        switch capture.prefix(while: { $0 != "." }) {
        case "keyword", "boolean", "attribute": return .keyword
        case "string", "character": return .string
        case "comment": return .comment
        case "number", "float": return .number
        case "type", "constructor", "label": return .type
        case "property": return language.colorsKeys ? .type : nil
        case "variable": return .plain
        default: return nil
        }
    }

    private static func grammar(for language: SourceLanguage) -> Grammar? {
        if let cached = grammars[language] { return cached }
        let grammar = loadGrammar(for: language)
        grammars[language] = grammar
        return grammar
    }

    private static func loadGrammar(for language: SourceLanguage) -> Grammar? {
        // TypeScript's queries refine JavaScript's, so they load after them.
        let javaScript = "TreeSitterJavaScript_TreeSitterJavaScript"
        let pointer: OpaquePointer
        let queries: [(bundle: String, file: String)]
        switch language {
        case .typeScript:
            pointer = tree_sitter_typescript()
            queries = [(javaScript, "highlights"), ("TreeSitterTypeScript_TreeSitterTypeScript", "highlights")]
        case .tsx:
            pointer = tree_sitter_tsx()
            queries = [(javaScript, "highlights"), (javaScript, "highlights-jsx"), ("TreeSitterTypeScript_TreeSitterTSX", "highlights")]
        case .javaScript:
            pointer = tree_sitter_javascript()
            queries = [(javaScript, "highlights"), (javaScript, "highlights-jsx")]
        case .json:
            pointer = tree_sitter_json()
            queries = [("TreeSitterJSON_TreeSitterJSON", "highlights")]
        case .markdown:
            pointer = tree_sitter_markdown()
            queries = [("TreeSitterMarkdown_TreeSitterMarkdown", "highlights")]
        case .yaml:
            pointer = tree_sitter_yaml()
            queries = [("TreeSitterYAML_TreeSitterYAML", "highlights")]
        case .properties, .shell:
            pointer = tree_sitter_bash()
            queries = [("TreeSitterBash_TreeSitterBash", "highlights")]
        case .swift:
            pointer = tree_sitter_swift()
            queries = [("TreeSitterSwift_TreeSitterSwift", "highlights")]
        case .plainText:
            return nil
        }

        var source = Data()
        for (bundle, file) in queries {
            guard
                let bundleURL = Bundle.main.url(forResource: bundle, withExtension: "bundle"),
                let url = Bundle(url: bundleURL)?.url(forResource: file, withExtension: "scm", subdirectory: "queries"),
                let data = try? Data(contentsOf: url)
            else { return nil }
            source.append(data)
            source.append(Data("\n".utf8))
        }
        let treeSitterLanguage = Language(pointer)
        guard let query = try? Query(language: treeSitterLanguage, data: source) else { return nil }
        return Grammar(language: treeSitterLanguage, query: query, laterPatternsWin: language != .json)
    }
}
