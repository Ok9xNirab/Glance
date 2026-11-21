//
//  MarkdownDocument.swift
//  Glance
//

import Foundation
import SwiftUI

/// A Markdown file parsed into blocks for the Files reader. Foundation's parser does the CommonMark and GFM work
/// (tables, task lists, strikethrough); this groups its runs back into the blocks they came from.
struct MarkdownDocument {
    struct Block: Identifiable {
        let id: Int
        let kind: Kind
        /// Inside an HTML block such as `<div align="center">`, which READMEs use to center their header.
        var isCentered = false
    }

    enum Kind {
        case paragraph(AttributedString)
        case heading(level: Int, text: AttributedString, anchor: String)
        case code(language: String?, text: String)
        case rule
        case list(ordered: Bool, start: Int, items: [ListItem])
        case quote([Block])
        case table(columns: [ColumnAlignment], header: [AttributedString], rows: [[AttributedString]])
        /// A paragraph or HTML block of nothing but images, like a README's header or badges.
        case images([Image])
    }

    struct ListItem: Identifiable {
        let id: Int
        /// `true` or `false` for a task list item, `nil` for a plain one.
        let checked: Bool?
        let blocks: [Block]
    }

    struct Image: Hashable {
        let url: URL
        let alt: String
        var link: URL?
        var width: CGFloat?
    }

    enum ColumnAlignment {
        case leading, center, trailing
    }

    let blocks: [Block]

    /// Parses `text`, resolving relative links and images against `baseURL`, the file's own URL.
    init(_ text: String, baseURL: URL) {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: Self.encodingLinkedImages(text), options: options, baseURL: baseURL) else {
            blocks = [Block(id: 0, kind: .paragraph(AttributedString(text)))]
            return
        }
        var builder = Builder(baseURL: baseURL)
        blocks = builder.blocks(from: parsed)
    }

    /// Foundation drops an image that's inside a link, as README badges are (`[![CI](badge.svg)](actions)`), so
    /// the link is moved into the image's URL fragment, outside code blocks, and taken out again when it's read.
    private static func encodingLinkedImages(_ text: String) -> String {
        guard text.contains("[![") else { return text }
        var inFence = false
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            guard !inFence, line.contains("[![") else { return String(line) }
            return String(line).replacing(#/\[!\[([^\]]*)\]\(\s*(\S+?)(?:\s+"[^"]*")?\s*\)\]\(\s*(\S+?)(?:\s+"[^"]*")?\s*\)/#) { match in
                let link = String(match.output.3).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                return "![\(match.output.1)](\(match.output.2)#\(linkMarker)\(link))"
            }
        }
        return lines.joined(separator: "\n")
    }

    static let linkMarker = "glance-link="

    /// GitHub's heading anchors: lowercased, punctuation dropped, spaces as hyphens.
    static func slug(_ text: String) -> String {
        let kept = text.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == " "
        }
        return String(String.UnicodeScalarView(kept)).replacingOccurrences(of: " ", with: "-")
    }
}

private struct Builder {
    /// A block from the parser, holding either the text of a leaf block or the blocks inside it.
    final class Node {
        let kind: PresentationIntent.Kind?
        let identity: Int
        var children: [Node] = []
        var text = AttributedString()

        init(kind: PresentationIntent.Kind?, identity: Int) {
            self.kind = kind
            self.identity = identity
        }
    }

    let baseURL: URL
    private var anchors: [String: Int] = [:]
    private var nextHTMLIdentity = -2

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    mutating func blocks(from parsed: AttributedString) -> [MarkdownDocument.Block] {
        let root = Node(kind: nil, identity: -1)
        for run in parsed.runs {
            let isHTML = run.inlinePresentationIntent?.contains(.inlineHTML) == true
            let components = run.presentationIntent?.components.reversed() ?? []
            if components.isEmpty {
                // Block-level HTML has no presentation intent of its own.
                guard run.inlinePresentationIntent?.contains(.blockHTML) == true else { continue }
                let node = Node(kind: nil, identity: nextHTMLIdentity)
                nextHTMLIdentity -= 1
                node.text = AttributedString(parsed[run.range])
                root.children.append(node)
                continue
            }
            var node = root
            for component in components {
                if let last = node.children.last, last.identity == component.identity {
                    node = last
                } else {
                    let child = Node(kind: component.kind, identity: component.identity)
                    node.children.append(child)
                    node = child
                }
            }
            if isHTML {
                // Inline tags: keep line breaks, drop the rest.
                let tag = String(parsed[run.range].characters).lowercased()
                if tag.hasPrefix("<br") { node.text.append(AttributedString("\n")) }
            } else {
                node.text.append(parsed[run.range])
            }
        }
        // Top-level blocks between an opening `<div align="center">` (or `<p>`) and its closing tag are centered.
        var isCentered = false
        var blocks: [MarkdownDocument.Block] = []
        for node in root.children {
            var centersThis = isCentered
            if node.kind == nil {
                let html = String(node.text.characters).lowercased()
                let opens = html.contains(#/<(div|p)\b[^>]*align\s*=\s*["']?center/#)
                let closes = html.contains(#/<\/(div|p)\s*>/#)
                if opens {
                    centersThis = true
                    if !closes { isCentered = true }
                } else if closes {
                    isCentered = false
                }
            }
            if let kind = block(node) {
                blocks.append(MarkdownDocument.Block(id: node.identity, kind: kind, isCentered: centersThis))
            }
        }
        return blocks
    }

    private mutating func blocks(_ nodes: [Node]) -> [MarkdownDocument.Block] {
        nodes.compactMap { node in block(node).map { MarkdownDocument.Block(id: node.identity, kind: $0) } }
    }

    private mutating func block(_ node: Node) -> MarkdownDocument.Kind? {
        guard let kind = node.kind else { return html(String(node.text.characters)) }
        switch kind {
        case .paragraph:
            if let images = imagesOnly(node.text) { return .images(images) }
            return .paragraph(styled(node.text))
        case let .header(level):
            let text = styled(node.text)
            return .heading(level: level, text: text, anchor: anchor(for: String(node.text.characters)))
        case let .codeBlock(languageHint):
            var code = String(node.text.characters)
            if code.hasSuffix("\n") { code.removeLast() }
            return .code(language: languageHint, text: code)
        case .thematicBreak:
            return .rule
        case .orderedList, .unorderedList:
            var start = 1
            if case let .listItem(ordinal) = node.children.first?.kind { start = ordinal }
            let items = node.children.map { item in
                var blocks = blocks(item.children)
                let checked = Self.takeCheckbox(&blocks)
                return MarkdownDocument.ListItem(id: item.identity, checked: checked, blocks: blocks)
            }
            if case .orderedList = kind { return .list(ordered: true, start: start, items: items) }
            return .list(ordered: false, start: start, items: items)
        case .blockQuote:
            return .quote(blocks(node.children))
        case let .table(columns):
            let alignments: [MarkdownDocument.ColumnAlignment] = columns.map {
                switch $0.alignment {
                case .center: .center
                case .right: .trailing
                default: .leading
                }
            }
            func cells(_ row: Node) -> [AttributedString] {
                var cells = Array(repeating: AttributedString(), count: alignments.count)
                for cell in row.children {
                    if case let .tableCell(column) = cell.kind, cells.indices.contains(column) {
                        cells[column] = styled(cell.text)
                    }
                }
                return cells
            }
            var header: [AttributedString] = []
            var rows: [[AttributedString]] = []
            for row in node.children {
                if case .tableHeaderRow = row.kind { header = cells(row) } else { rows.append(cells(row)) }
            }
            return .table(columns: alignments, header: header, rows: rows)
        default:
            // Anything else holds blocks; show them in place.
            let inner = blocks(node.children)
            return inner.isEmpty ? nil : .quote(inner)
        }
    }

    /// `[ ] ` or `[x] ` opening a list item's first paragraph makes it a task.
    private static func takeCheckbox(_ blocks: inout [MarkdownDocument.Block]) -> Bool? {
        guard let first = blocks.first, case var .paragraph(text) = first.kind else { return nil }
        let prefix = String(text.characters.prefix(4))
        let checked: Bool
        switch prefix.lowercased() {
        case "[ ] ": checked = false
        case "[x] ": checked = true
        default: return nil
        }
        text.removeSubrange(text.startIndex..<text.index(text.startIndex, offsetByCharacters: 4))
        blocks[0] = MarkdownDocument.Block(id: first.id, kind: .paragraph(text))
        return checked
    }

    /// Inline code in the mono font on a tinted background; the rest SwiftUI styles from the parsed intents.
    private func styled(_ text: AttributedString) -> AttributedString {
        var text = text
        for run in text.runs where run.inlinePresentationIntent?.contains(.code) == true {
            text[run.range].swiftUI.font = .mono(13)
            text[run.range].swiftUI.backgroundColor = Palette.segment
        }
        for run in text.runs where run.imageURL != nil {
            // An image among text shows as its alt text.
            text[run.range].swiftUI.foregroundColor = Palette.secondaryText
        }
        return text
    }

    private mutating func anchor(for title: String) -> String {
        let slug = MarkdownDocument.slug(title)
        let count = anchors[slug, default: 0]
        anchors[slug] = count + 1
        return count == 0 ? slug : "\(slug)-\(count)"
    }

    /// The images of a paragraph that has nothing else but whitespace, or `nil` when it has text.
    private func imagesOnly(_ text: AttributedString) -> [MarkdownDocument.Image]? {
        var images: [MarkdownDocument.Image] = []
        for run in text.runs {
            if let url = run.imageURL {
                images.append(image(url, alt: String(text[run.range].characters), link: run.link))
            } else if !String(text[run.range].characters).allSatisfy(\.isWhitespace) {
                return nil
            }
        }
        return images.isEmpty ? nil : images
    }

    /// Block HTML, which READMEs mostly use to center a logo or badges: its images, or else its text without tags.
    private func html(_ html: String) -> MarkdownDocument.Kind? {
        var images: [MarkdownDocument.Image] = []
        var link: URL?
        let tags = html.matches(of: #/<\s*(\/?)\s*(img|a)\b([^>]*)>/#.ignoresCase())
        for tag in tags {
            let name = tag.output.2.lowercased()
            let attributes = String(tag.output.3)
            if name == "a" {
                link = tag.output.1.isEmpty ? Self.attribute("href", in: attributes).flatMap(resolve) : nil
            } else if let src = Self.attribute("src", in: attributes), let url = resolve(src) {
                let width = Self.attribute("width", in: attributes).flatMap { Double($0) }.map { CGFloat($0) }
                images.append(MarkdownDocument.Image(url: url, alt: Self.attribute("alt", in: attributes) ?? "", link: link, width: width))
            }
        }
        if !images.isEmpty { return .images(images) }

        let text = html
            .replacing(#/<!--[\s\S]*?-->/#, with: "")
            .replacing(#/<\s*br\s*\/?>/#.ignoresCase(), with: "\n")
            .replacing(#/<[^>]+>/#, with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : .paragraph(AttributedString(text))
    }

    /// An image, with the link `encodingLinkedImages` put in its fragment taken back out.
    private func image(_ url: URL, alt: String, link: URL?) -> MarkdownDocument.Image {
        let url = url.absoluteURL
        guard
            let fragment = url.fragment(percentEncoded: true), fragment.hasPrefix(MarkdownDocument.linkMarker),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return MarkdownDocument.Image(url: url, alt: alt, link: link) }
        components.fragment = nil
        let href = fragment.dropFirst(MarkdownDocument.linkMarker.count).removingPercentEncoding
        return MarkdownDocument.Image(url: components.url ?? url, alt: alt, link: href.flatMap(resolve) ?? link)
    }

    private func resolve(_ string: String) -> URL? {
        URL(string: string, relativeTo: baseURL)?.absoluteURL
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = try? Regex<(Substring, Substring)>("(?i)\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']")
        guard let pattern, let match = attributes.firstMatch(of: pattern) else { return nil }
        return String(match.output.1)
    }
}
