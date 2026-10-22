//
//  ChangesColumn.swift
//  Glance
//

import SwiftUI

struct ChangesColumn: View {
    @Bindable var changes: ChangesModel
    @Environment(\.glanceAccent) private var accent

    var body: some View {
        ListColumn {
            VStack(spacing: 10) {
                ViewModePicker()
                SearchField("Filter", text: $changes.filter)
                if !changes.files.isEmpty {
                    stageAllRow
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if changes.files.isEmpty {
                PaneMessage("No changes. The working tree is clean.")
            } else if changes.visibleFiles.isEmpty {
                PaneMessage("No files match “\(changes.filter)”")
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(changes.visibleFiles) { file in
                            ChangedFileRow(file: file, changes: changes)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }

            if !changes.files.isEmpty {
                reviewProgress
            }
            commitArea
        }
    }

    private var stageAllRow: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { changes.allStaged }, set: { _ in changes.toggleAllStaged() })) {
                Text("\(changes.stagedPaths.count) of \(changes.files.count) staged")
                    .foregroundStyle(Palette.secondaryText)
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            LineStats(additions: changes.totalAdditions, deletions: changes.totalDeletions)
        }
        .font(.system(size: 12))
    }

    private var reviewProgress: some View {
        HStack(spacing: 8) {
            Text("Reviewed \(changes.viewedPaths.count) of \(changes.files.count)")
                .fixedSize()
            Capsule()
                .fill(Palette.selection)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(accent)
                            .frame(width: proxy.size.width * changes.reviewProgress)
                            .animation(.easeOut(duration: 0.25), value: changes.reviewProgress)
                    }
                }
                .accessibilityHidden(true)
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.secondaryText)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var commitArea: some View {
        let stagedCount = changes.stagedPaths.count
        return VStack(spacing: 8) {
            BoxedTextField("Summary", text: $changes.summary)
            BoxedTextEditor("Description", text: $changes.details)
            Button(action: changes.commit) {
                Text("Commit \(stagedCount) \(stagedCount == 1 ? "File" : "Files")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(accent)
                            .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!changes.canCommit)
            .opacity(changes.canCommit ? 1 : 0.45)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
        .overlay(alignment: .top) { Hairline() }
    }
}

private struct ChangedFileRow: View {
    let file: ChangedFile
    let changes: ChangesModel
    @Environment(\.glanceAccent) private var accent
    @State private var isHovered = false

    var body: some View {
        let isSelected = file.id == changes.selectedPath
        let isViewed = changes.isViewed(file)
        HStack(spacing: 8) {
            Toggle("Stage \(file.diff.path)", isOn: Binding(
                get: { changes.isStaged(file) },
                set: { changes.setStaged(file, $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Button {
                changes.select(file)
            } label: {
                HStack(spacing: 7) {
                    StatusBadge(status: file.diff.status, inverted: isSelected)
                    FileIcon(name: file.diff.name, inverted: isSelected)
                    Text("\(Text(file.diff.directory).foregroundStyle(isSelected ? Color.white.opacity(0.82) : Palette.secondaryText))\(Text(file.diff.name).foregroundStyle(isSelected ? .white : isViewed ? Palette.secondaryText : Palette.text))")
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let ago = file.agentEditedAgo {
                        AgentDot(color: isSelected ? .white : Palette.agentDot)
                            .help("Agent changed this \(ago) ago")
                    }
                    if isViewed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isSelected ? .white : Palette.secondaryText)
                            .accessibilityLabel("Viewed")
                    }
                    LineStats(additions: file.diff.additions, deletions: file.diff.deletions, inverted: isSelected)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? accent : isHovered ? Palette.hover : .clear)
        )
        .onHover { isHovered = $0 }
    }
}
