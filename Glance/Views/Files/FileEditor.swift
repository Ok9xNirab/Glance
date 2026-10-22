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
                if let content = files.activeContent, let language, let path = files.activePath {
                    CodeView(path: path, content: content, language: language, files: files) {
                        model.copy($0, as: .path)
                    }
                    Minimap(content: content)
                } else {
                    PaneMessage(files.activePath == nil
                        ? "No file open. Pick one from the tree or press ⌘P."
                        : "This file's contents aren't included in the sample data.")
                }
            }

            StatusBar {
                Text(files.activeContent == nil ? "Line 0, Column 0" : "Line \(files.currentLine), Column \(files.currentColumn)")
                if files.activeContent != nil, files.selectedLines.count > 1 {
                    Text("\(files.selectedLines.count) lines selected")
                }
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

extension FileContent.Mark {
    var barColor: Color {
        switch self {
        case .added: Palette.addedBar
        case .modified: Palette.modifiedBar
        }
    }
}
