//
//  FileEditor.swift
//  Glance
//

import SwiftUI

struct FileEditor: View {
    let files: FilesModel
    @Environment(AppModel.self) private var model

    var body: some View {
        let language = files.activePath.map { SourceLanguage(path: $0) }
        VStack(spacing: 0) {
            toolbar
            EditorTabBar(files: files)

            HStack(spacing: 0) {
                if let content = files.activeContent, let language {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(content.lines.enumerated()), id: \.offset) { index, line in
                                EditorLine(
                                    number: index + 1,
                                    text: SyntaxHighlighter.highlight(line, as: language),
                                    mark: content.marks[index + 1],
                                    isCurrent: index + 1 == files.currentLine
                                ) {
                                    files.currentLine = index + 1
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .id(files.activePath)
                    Minimap(content: content)
                } else {
                    PaneMessage(files.activePath == nil
                        ? "No file open. Pick one from the tree or press ⌘P."
                        : "This file's contents aren't included in the sample data.")
                }
            }

            StatusBar {
                Text("Line \(files.activeContent == nil ? 0 : files.currentLine), Column 1")
                Text(language?.rawValue ?? "—")
                Text("Spaces: 2")
                Text("UTF-8 · LF")
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
                IconButton("folder", help: "Reveal in Finder") {}
                IconButton("arrow.up.forward.square", help: "Open in Editor (⌘O)") {}
            } else {
                Spacer()
            }
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

private struct EditorLine: View {
    let number: Int
    let text: AttributedString
    let mark: FileContent.Mark?
    let isCurrent: Bool
    let select: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(mark?.barColor ?? .clear)
                .frame(width: 3)
            Text("\(number)")
                .foregroundStyle(isCurrent ? Palette.text : Palette.gutter)
                .padding(.trailing, 14)
                .frame(width: 46, alignment: .trailing)
            Text(text)
                .foregroundStyle(Palette.code)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 24)
            Spacer(minLength: 0)
        }
        .font(.mono(12))
        .frame(height: 20)
        .background(isCurrent ? Palette.currentLine : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}

/// A scaled-down outline of the file, with changed lines tinted.
private struct Minimap: View {
    let content: FileContent

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(content.lines.enumerated()), id: \.offset) { index, line in
                let indent = line.prefix { $0 == " " }.count
                let length = line.trimmingCharacters(in: .whitespaces).count
                HStack(spacing: 0) {
                    Color.clear.frame(width: CGFloat(min(indent, 30)) * 1.1)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(content.marks[index + 1]?.barColor ?? Palette.minimapLine)
                        .frame(width: CGFloat(min(length, 62)) * 1.1, height: 2)
                }
                .frame(height: 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: 92, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) {
            Palette.minimapViewport
                .frame(height: CGFloat(min(content.lines.count, 40) * 3 + 4))
                .padding(.top, 8)
        }
        .clipped()
        .overlay(alignment: .leading) { Hairline(axis: .vertical) }
        .accessibilityHidden(true)
    }
}

private extension FileContent.Mark {
    var barColor: Color {
        switch self {
        case .added: Palette.addedBar
        case .modified: Palette.modifiedBar
        }
    }
}
