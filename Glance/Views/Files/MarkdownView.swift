//
//  MarkdownView.swift
//  Glance
//

import AppKit
import Foundation
import SwiftUI

/// The Files reader for a Markdown file, rendered the way GitHub shows a README. Relative links open the file
/// in Files, `#anchor` links scroll to their heading, and everything else opens in the default app.
struct MarkdownView: View {
    let path: String
    let content: FileContent
    let files: FilesModel
    @Environment(\.glanceAccent) private var accent
    @State private var document: MarkdownDocument?

    private var fileURL: URL { files.url.appending(path: path) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let document {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(document.blocks) { block in
                            MarkdownBlockView(block: block, depth: 0)
                                .multilineTextAlignment(block.isCentered ? .center : .leading)
                                .frame(maxWidth: .infinity, alignment: block.isCentered ? .center : .leading)
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                }
            }
            .environment(\.openURL, OpenURLAction { open($0, proxy: proxy) })
        }
        .font(.system(size: 14))
        .foregroundStyle(Palette.text)
        .tint(accent)
        .textSelection(.enabled)
        .background(Palette.window)
        .id(path)
        .task(id: content.lines) {
            document = MarkdownDocument(content.lines.joined(separator: "\n"), baseURL: fileURL)
        }
    }

    private func open(_ url: URL, proxy: ScrollViewProxy) -> OpenURLAction.Result {
        guard url.isFileURL else { return .systemAction }
        let root = files.url.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        let relative = target.hasPrefix(root + "/") ? String(target.dropFirst(root.count + 1)) : nil
        if relative == path || target == fileURL.standardizedFileURL.path {
            if let fragment = url.fragment(percentEncoded: false), !fragment.isEmpty {
                withAnimation(.snappy) { proxy.scrollTo(MarkdownDocument.slug(fragment), anchor: .top) }
            }
            return .handled
        }
        if let relative, files.allFiles.contains(where: { $0.path == relative }) {
            files.open(relative, pinned: true)
            return .handled
        }
        if FileManager.default.fileExists(atPath: target) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: target)])
            return .handled
        }
        return .discarded
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownDocument.Block
    let depth: Int

    var body: some View {
        switch block.kind {
        case let .paragraph(text):
            Text(text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case let .heading(level, text, anchor):
            Heading(level: level, text: text)
                .id(anchor)
        case let .code(language, text):
            CodeBlock(language: language, code: text)
        case .rule:
            Rectangle()
                .fill(Palette.separator)
                .frame(height: 2)
                .padding(.vertical, 6)
        case let .list(ordered, start, items):
            MarkdownList(ordered: ordered, start: start, items: items, depth: depth)
        case let .quote(blocks):
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.separator)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(blocks) { MarkdownBlockView(block: $0, depth: depth) }
                }
                .foregroundStyle(Palette.secondaryText)
                .padding(.vertical, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
        case let .table(columns, header, rows):
            MarkdownTable(columns: columns, header: header, rows: rows)
        case let .images(images):
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(images.enumerated()), id: \.offset) { MarkdownImage(image: $0.element) }
            }
        }
    }
}

private struct Heading: View {
    let level: Int
    let text: AttributedString

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(level == 6 ? Palette.secondaryText : Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            if level <= 2 {
                Hairline()
            }
        }
        .padding(.top, level <= 2 ? 10 : 6)
    }

    private var size: CGFloat {
        switch level {
        case 1: 28
        case 2: 22
        case 3: 18
        case 4: 15
        default: 13.5
        }
    }
}

private struct MarkdownList: View {
    let ordered: Bool
    let start: Int
    let items: [MarkdownDocument.ListItem]
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(for: item, at: index)
                        .frame(minWidth: 16, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(item.blocks) { MarkdownBlockView(block: $0, depth: depth + 1) }
                    }
                }
            }
        }
        .padding(.leading, 6)
    }

    @ViewBuilder
    private func marker(for item: MarkdownDocument.ListItem, at index: Int) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.secondaryText))
        } else if ordered {
            Text("\(start + index).")
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryText)
        } else {
            Text(["•", "◦", "▪︎"][depth % 3])
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

private struct CodeBlock: View {
    let language: String?
    let code: String
    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(highlighted)
                .lineSpacing(3)
                .fixedSize()
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.column))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.separator, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if isHovered {
                IconButton(copied ? "checkmark" : "doc.on.doc", help: copied ? "Copied" : "Copy Code", size: 26) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.window))
                .padding(6)
            }
        }
        .onHover { isHovered = $0 }
    }

    private var highlighted: AttributedString {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let language = SourceLanguage(languageHint: language)
        let spans = SyntaxHighlighter.spans(for: lines, as: language)
        var text = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { text.append(AttributedString("\n")) }
            text.append(AttributedString(code: line, spans: spans[index], size: 12.5))
        }
        return text
    }
}

private struct MarkdownTable: View {
    let columns: [MarkdownDocument.ColumnAlignment]
    let header: [AttributedString]
    let rows: [[AttributedString]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                if !header.isEmpty {
                    row(header, isHeader: true, background: Palette.column)
                }
                ForEach(rows.indices, id: \.self) { index in
                    row(rows[index], isHeader: false, background: index.isMultiple(of: 2) ? Palette.window : Palette.column)
                }
            }
            .overlay(Rectangle().strokeBorder(Palette.separator, lineWidth: 1))
        }
    }

    private func row(_ cells: [AttributedString], isHeader: Bool, background: Color) -> some View {
        GridRow {
            ForEach(cells.indices, id: \.self) { column in
                Text(cells[column])
                    .fontWeight(isHeader ? .semibold : .regular)
                    .frame(maxWidth: 420, alignment: alignment(column))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(column))
                    .background(background)
                    .overlay(Rectangle().strokeBorder(Palette.separator, lineWidth: 0.5))
            }
        }
    }

    private func alignment(_ column: Int) -> Alignment {
        switch columns.indices.contains(column) ? columns[column] : .leading {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// An image from the worktree or the web, at its natural size up to the reader's width.
private struct MarkdownImage: View {
    let image: MarkdownDocument.Image
    @Environment(\.openURL) private var openURL
    @State private var loaded: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let loaded {
                let width = image.width ?? loaded.size.width
                let height = loaded.size.width > 0 ? width * loaded.size.height / loaded.size.width : loaded.size.height
                Image(nsImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: width, maxHeight: height)
            } else if failed {
                Label(image.alt.isEmpty ? image.url.lastPathComponent : image.alt, systemImage: "photo")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Palette.segment))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.segment)
                    .frame(width: image.width ?? 80, height: 20)
            }
        }
        .onTapGesture { if let link = image.link { openURL(link) } }
        .help(image.alt)
        .task(id: image.url) { await load() }
    }

    private func load() async {
        let url = image.url
        let data: Data?
        if url.isFileURL {
            data = await Task.detached { try? Data(contentsOf: url) }.value
        } else {
            data = try? await URLSession.shared.data(from: url).0
        }
        if let data, let image = NSImage(data: data), image.size.width > 0 {
            loaded = image
        } else {
            failed = true
        }
    }
}

extension SourceLanguage {
    /// The language a fenced code block's info string names, such as `ts`, `bash` or `json`.
    init(languageHint: String?) {
        switch languageHint?.lowercased().split(separator: " ").first {
        case "typescript": self = .typeScript
        case "javascript": self = .javaScript
        case "shell", "console", "shellsession", "sh-session": self = .shell
        case "markdown": self = .markdown
        case "jsonc", "json5": self = .json
        case "dotenv", "ini", "properties": self = .properties
        case let hint?: self = SourceLanguage(path: "file.\(hint)")
        case nil: self = .plainText
        }
    }
}
