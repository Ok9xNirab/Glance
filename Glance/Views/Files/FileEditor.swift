//
//  FileEditor.swift
//  Glance
//

import AppKit
import SwiftUI

struct FileEditor: View {
    let files: FilesModel
    @Environment(AppModel.self) private var model
    @State private var scroll = EditorScroll()

    var body: some View {
        let language = files.activePath.map { SourceLanguage(path: $0) }
        VStack(spacing: 0) {
            toolbar
            EditorTabBar(files: files)

            HStack(spacing: 0) {
                if let content = files.activeContent, let path = files.activePath, files.showsReader(path) {
                    MarkdownView(path: path, content: content, files: files)
                } else if let content = files.activeContent, let language, let path = files.activePath {
                    CodeView(path: path, content: content, language: language, files: files, scroll: scroll) {
                        model.copy($0, as: .path)
                    }
                    Minimap(content: content, scroll: scroll)
                } else if let message = files.activeMessage {
                    PaneMessage(message)
                } else {
                    // Still reading the file.
                    Palette.window
                }
            }

            StatusBar {
                let content = files.activeContent
                let isReading = files.activePath.map(files.showsReader) ?? false
                if isReading {
                    Text(content.map { "\($0.lines.count) lines" } ?? "")
                } else {
                    Text(content == nil ? "Line 0, Column 0" : "Line \(files.currentLine), Column \(files.currentColumn)")
                }
                if content != nil, !isReading, files.selectedLines.count > 1 {
                    Text("\(files.selectedLines.count) lines selected")
                }
                Text(isReading ? "Markdown Preview" : language?.rawValue ?? "—")
                if let content {
                    if let indentation = content.indentation { Text(indentation) }
                    Text("UTF-8 · \(content.lineEnding)")
                }
                Spacer(minLength: 0)
                Text("\(files.allFiles.count) files · \(files.changedCount) changed")
                ShortcutHint(keys: ["⌘P"], label: "go to file")
                ShortcutHint(keys: ["⌃G"], label: "go to line")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.window)
    }

    private var toolbar: some View {
        TopBar(spacing: 6, leading: 16) {
            if let path = files.activePath {
                Breadcrumbs(path: path)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if files.isMarkdown(path) {
                    PillPicker(
                        selection: Binding(get: { files.showsReader(path) }, set: { files.setShowsReader($0, for: path) }),
                        items: [.init(true, "Preview"), .init(false, "Source")]
                    )
                }
                if let status = files.status(of: path) {
                    Button {
                        model.showDiff(forPath: path)
                    } label: {
                        HStack(spacing: 6) {
                            StatusBadge(status: status, size: 15)
                            Text("View Diff")
                        }
                    }
                    .buttonStyle(BezelButtonStyle())
                }
                ToolbarSeparator()
                IconButton(
                    model.recentlyCopied == .path ? "checkmark" : "link",
                    help: model.recentlyCopied == .path ? "Path Copied" : "Copy Relative Path (⌥⌘C)"
                ) {
                    model.copy(path, as: .path)
                }
                IconButton("folder", help: "Reveal in Finder") { revealInFinder(path) }
            } else {
                Spacer()
            }
        }
    }

    /// Selects the file in Finder, or opens the worktree's folder when the file isn't there.
    private func revealInFinder(_ path: String) {
        let url = model.currentWorktree.url.appending(path: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(model.currentWorktree.url)
        }
    }
}

private struct Breadcrumbs: View {
    let path: String

    var body: some View {
        let parts = path.split(separator: "/").map(String.init)
        HStack(spacing: 4) {
            ForEach(parts.indices, id: \.self) { index in
                let isLast = index == parts.count - 1
                Text(parts[index])
                    .fontWeight(isLast ? .semibold : .regular)
                    .foregroundStyle(isLast ? Palette.text : Palette.secondaryText)
                if !isLast {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .font(.mono(12))
        .lineLimit(1)
    }
}

private struct EditorTabBar: View {
    let files: FilesModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(files.tabs) { tab in
                    EditorTab(tab: tab, files: files)
                }
            }
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tabBar)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

private struct EditorTab: View {
    let tab: FilesModel.Tab
    let files: FilesModel
    @Environment(\.glanceAccent) private var accent
    @State private var isCloseHovered = false

    var body: some View {
        let isActive = tab.path == files.activePath
        HStack(spacing: 2) {
            Button {
                files.activate(tab)
            } label: {
                HStack(spacing: 6) {
                    if let status = files.status(of: tab.path) {
                        StatusBadge(status: status, size: 13)
                    }
                    FileIcon(name: tab.path.pathName, size: 11)
                    Text(tab.path.pathName)
                        .italic(tab.isPreview)
                        .lineLimit(1)
                }
                .font(.system(size: 12))
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tab.path)
            .simultaneousGesture(TapGesture(count: 2).onEnded { files.open(tab.path, pinned: true) })

            Button {
                files.close(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 4).fill(isCloseHovered ? Palette.hover : .clear))
                    .opacity(isCloseHovered ? 1 : 0.55)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .accessibilityLabel("Close \(tab.path.pathName)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(maxWidth: 220, maxHeight: .infinity)
        .foregroundStyle(isActive ? Palette.text : Palette.secondaryText)
        .background(isActive ? Palette.window : .clear)
        .overlay(alignment: .top) {
            if isActive { accent.frame(height: 2) }
        }
        .overlay(alignment: .trailing) { Hairline(axis: .vertical) }
    }
}

/// A scaled-down outline of the file, with changed lines tinted. Like Xcode's, it shades the lines in view,
/// scrolls along with a file too long to fit, and clicking or dragging it scrolls the code.
private struct Minimap: View {
    let content: FileContent
    let scroll: EditorScroll
    /// How far below the viewport's top the drag took hold of it, or `nil` when not dragging.
    @State private var grab: CGFloat?

    private static let rowHeight: CGFloat = 3
    private static let inset = EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)

    var body: some View {
        GeometryReader { proxy in
            let layout = Layout(lines: content.lines.count, scroll: scroll, height: proxy.size.height - Self.inset.top - Self.inset.bottom)
            ZStack(alignment: .topLeading) {
                Palette.minimapViewport
                    .frame(height: layout.viewportHeight + 4)
                    .offset(y: Self.inset.top - 2 + layout.viewportTop)
                // Drawn rather than laid out, and only as far as it shows, since a real file can run to thousands of lines.
                Canvas { context, size in
                    let first = max(0, Int(layout.offset / Self.rowHeight))
                    let last = min(content.lines.count, first + Int(size.height / Self.rowHeight) + 2)
                    guard first < last else { return }
                    for index in first..<last {
                        let line = content.lines[index]
                        let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                        let length = line.trimmingCharacters(in: .whitespaces).count
                        guard length > 0 else { continue }
                        let rect = CGRect(
                            x: CGFloat(min(indent, 30)) * 1.1, y: CGFloat(index) * Self.rowHeight - layout.offset,
                            width: CGFloat(min(length, 62)) * 1.1, height: 2
                        )
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(content.marks[index + 1]?.barColor ?? Palette.minimapLine))
                    }
                }
                .padding(Self.inset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let y = drag.location.y - Self.inset.top
                        if grab == nil {
                            let top = layout.viewportTop
                            // Grabbing the viewport keeps hold of it where it was taken; elsewhere, it centers there.
                            grab = (top...(top + layout.viewportHeight)).contains(y) ? y - top : layout.viewportHeight / 2
                        }
                        scroll.scrollTo(layout.line(forViewportTop: y - (grab ?? 0)))
                    }
                    .onEnded { _ in grab = nil }
            )
        }
        .frame(width: 92)
        .clipped()
        .overlay(alignment: .leading) { Hairline(axis: .vertical) }
        .accessibilityHidden(true)
    }

    /// Where the outline and viewport sit. The viewport moves like a scroller's knob: from the top of the outline
    /// to the bottom of what shows of it, and a file too long to fit scrolls the outline along with it.
    private struct Layout {
        let viewportTop: CGFloat
        let viewportHeight: CGFloat
        /// How far the outline is scrolled up.
        let offset: CGFloat
        private let track: CGFloat
        private let scrollableLines: Double

        init(lines: Int, scroll: EditorScroll, height: CGFloat) {
            let row = Minimap.rowHeight
            let outline = CGFloat(lines) * row
            viewportHeight = CGFloat(scroll.visibleLines) * row
            scrollableLines = max(Double(lines) - scroll.visibleLines, 0)
            let overflow = max(outline - height, 0)
            track = max(scrollableLines * row - overflow, 0)
            let progress = scrollableLines > 0 ? min(max(scroll.top / scrollableLines, 0), 1) : 0
            offset = progress * overflow
            viewportTop = progress * track
        }

        func line(forViewportTop top: CGFloat) -> Double {
            guard track > 0 else { return 0 }
            return Double(min(max(top / track, 0), 1)) * scrollableLines
        }
    }
}

extension FileContent.Mark {
    var barColor: Color {
        switch self {
        case .added: Palette.addedBar
        case .modified: Palette.modifiedBar
        }
    }
}
