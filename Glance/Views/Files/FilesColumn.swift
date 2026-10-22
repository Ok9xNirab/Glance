//
//  FilesColumn.swift
//  Glance
//

import SwiftUI

struct FilesColumn: View {
    @Bindable var files: FilesModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ListColumn {
            VStack(spacing: 10) {
                ViewModePicker()
                SearchField("Go to File…", text: $files.query, shortcut: "⌘P", isFocused: $isSearchFocused)
                HStack(spacing: 8) {
                    Toggle("Changed only", isOn: $files.changedOnly)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    Text("Changed only")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { files.changedOnly.toggle() }
                    IconButton("rectangle.compress.vertical", help: "Collapse All", size: 22, action: files.collapseAll)
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            let rows = files.rows
            if rows.isEmpty {
                if files.isLoaded {
                    PaneMessage(!files.query.isEmpty ? "No files match “\(files.query)”" : files.changedOnly ? "No changed files." : "No files.")
                } else {
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            FileTreeRow(row: row, files: files)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .onChange(of: files.wantsSearchFocus, initial: true) {
            guard files.wantsSearchFocus else { return }
            isSearchFocused = true
            files.wantsSearchFocus = false
        }
    }
}

private struct FileTreeRow: View {
    let row: FilesModel.TreeRow
    let files: FilesModel
    @Environment(\.glanceAccent) private var accent

    var body: some View {
        let node = row.node
        let isSelected = !node.isFolder && node.path == files.activePath
        let isExpanded = files.isExpanded(node)
        let iconColor: Color = isSelected ? .white.opacity(0.85) : accent

        Button {
            if node.isFolder {
                files.toggleFolder(node)
            } else {
                files.open(node.path, pinned: false)
            }
        } label: {
            HStack(spacing: 5) {
                Group {
                    if node.isFolder {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .foregroundStyle(isSelected ? .white.opacity(0.85) : Palette.secondaryText)
                .frame(width: 12)

                if node.isFolder {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(iconColor)
                        .frame(width: 16)
                } else {
                    FileIcon(name: node.name, inverted: isSelected)
                }

                HStack(spacing: 6) {
                    Text(node.name)
                    if row.showsParent {
                        Text(node.parentPath)
                            .font(.mono(11))
                            .foregroundStyle(isSelected ? .white.opacity(0.85) : Palette.secondaryText)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                if node.isFolder, row.containsChanges, !isExpanded {
                    Circle()
                        .fill(isSelected ? .white : Palette.modifiedBar)
                        .frame(width: 6, height: 6)
                        .help("Contains changes")
                }
                if let status = row.status {
                    StatusBadge(status: status, size: 15, inverted: isSelected)
                }
            }
            .foregroundStyle(isSelected ? .white : Palette.text)
            .padding(.leading, 6 + CGFloat(row.depth) * 14)
            .padding(.trailing, 8)
            .frame(height: 24)
        }
        .buttonStyle(RowButtonStyle(cornerRadius: 5, fill: isSelected ? accent : nil))
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !node.isFolder { files.open(node.path, pinned: true) }
        })
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
