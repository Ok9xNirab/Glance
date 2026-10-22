//
//  Chrome.swift
//  Glance
//

import SwiftUI

struct Hairline: View {
    var axis: Axis = .horizontal

    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}

/// The short vertical rule between toolbar groups.
struct ToolbarSeparator: View {
    var body: some View {
        Hairline(axis: .vertical)
            .frame(height: 18)
            .padding(.horizontal, 4)
    }
}

/// The 52pt bar at the top of every pane. It doubles as the window's drag area, since the title bar is hidden.
struct TopBar<Content: View>: View {
    var spacing: CGFloat = 6
    var leading: CGFloat = 12
    var showsSeparator = true
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: spacing) { content }
            .padding(.leading, leading)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .overlay(alignment: .bottom) {
                if showsSeparator { Hairline() }
            }
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
    }
}

struct StatusBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) { content }
            .font(.system(size: 11))
            .foregroundStyle(Palette.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 26)
            .overlay(alignment: .top) { Hairline() }
    }
}

/// The middle column shared by Changes, History and Files: repository header, then the view's own list.
struct ListColumn<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            RepositoryHeader()
            content
        }
        .frame(width: 330)
        .frame(maxHeight: .infinity)
        .background(Palette.column)
        .overlay(alignment: .trailing) { Hairline(axis: .vertical) }
    }
}

struct RepositoryHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.glanceAccent) private var accent

    var body: some View {
        let worktree = model.currentWorktree
        // Leave room for the traffic lights when the sidebar no longer covers them.
        TopBar(leading: model.isSidebarVisible ? 16 : 84) {
            if !model.isSidebarVisible {
                IconButton("sidebar.left", help: "Show Sidebar", action: model.toggleSidebar)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(model.repositoryName)
                    .font(.system(size: 13, weight: .bold))
                Text(model.previewedBranch.map { "Previewing \(Text($0.name).font(.mono(11)))" }
                    ?? "\(worktree.name) — \(Text(worktree.branch).font(.mono(11)))")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            IconButton("arrow.down.circle", help: "Fetch origin · 2 min ago") {}
            IconButton("arrow.up.circle", help: "Push \(worktree.aheadCount) commits") {}
                .overlay(alignment: .topTrailing) {
                    if worktree.aheadCount > 0 {
                        Text("\(worktree.aheadCount)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Capsule().fill(accent))
                            .offset(y: 1)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

struct ViewModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let changeCount = model.changes.files.count
        PillPicker(
            selection: $model.mode,
            items: [
                .init(.changes, "Changes", badge: changeCount > 0 ? changeCount : nil),
                .init(.history, "History"),
                .init(.files, "Files"),
            ],
            fillsWidth: true
        )
    }
}

struct DiffLayoutPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PillPicker(selection: $model.diffLayout, items: [.init(.unified, "Unified"), .init(.split, "Split")])
            .fixedSize()
    }
}

/// A centered secondary-text message for empty lists and panes.
struct PaneMessage: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(Palette.secondaryText)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
