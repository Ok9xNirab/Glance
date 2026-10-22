# Glance

macOS SwiftUI app: a git client for reviewing what AI agents change across worktrees. It currently runs a static design flow on sample data, with no real git access yet.

## Build

```sh
xcodebuild -project Glance.xcodeproj -scheme Glance -configuration Debug build
```

- Target is macOS 26.6, Swift 5 language mode, with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `MEMBER_IMPORT_VISIBILITY`, so every file must import the modules it uses (e.g. `Foundation` for `localizedCaseInsensitiveContains`).
- The `Glance/` folder is a file-system synchronized group: new files are picked up automatically, so don't edit `project.pbxproj` to add them.

## Layout

- `App/`: entry point, menu commands (⌘K, ⌘P, ⌘1–3, ⌘⇧C), Settings (appearance and accent).
- `Theme/`: `Palette` holds the design's light/dark color tokens; `glanceAccent` is an environment value.
- `Models/`: plain value types (`FileDiff`, `Commit`, `Worktree`, `FileNode`). `RawHunk` lines use `+`/`-`/space prefixes.
- `SampleData/`: all static content. Replace it with a git-backed source later.
- `State/`: `@Observable` models. `AppModel` owns one `ChangesModel` per worktree plus `HistoryModel` and `FilesModel`. Single-key shortcuts (J/K/V, arrows, ⌥S) go through `KeyboardShortcutMonitor`, which ignores keys while a text field is being edited.
- `Views/`: Sidebar, Changes, History, Files, and the ⌘K Switcher, plus shared `Components/`.

## Conventions

- Use `Palette` tokens rather than raw colors; use the accent from `@Environment(\.glanceAccent)`.
- Diff rows live in one `LazyVStack` with pinned hunk headers, so row IDs must be unique across hunks.
