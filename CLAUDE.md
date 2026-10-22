# Glance

macOS SwiftUI app: a git client for reviewing what AI agents change across worktrees. The sidebar, ⌘K switcher, ⌘T picker and Changes use real repositories; History and Files still show sample data. The App Sandbox is off so Glance can run `git` with the user's config, hooks and credentials.

## Build

```sh
xcodebuild -project Glance.xcodeproj -scheme Glance -configuration Debug build
```

- After every change, build and then run the app to check it, relaunching it if it's already open:

  ```sh
  pkill -x Glance; open "$(xcodebuild -project Glance.xcodeproj -scheme Glance -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/ {print $3}')/Glance.app"
  ```

- Target is macOS 26.6, Swift 5 language mode, with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `MEMBER_IMPORT_VISIBILITY`, so every file must import the modules it uses (e.g. `Foundation` for `localizedCaseInsensitiveContains`).
- The `Glance/` folder is a file-system synchronized group: new files are picked up automatically, so don't edit `project.pbxproj` to add them.

## Layout

- `App/`: entry point, menu commands (⌘O, ⌘K, ⌘T, ⌘P, ⌘1–3, ⌘⇧C).
- `Theme/`: `Palette` holds the design's light/dark color tokens; `glanceAccent` is an environment value.
- `Git/`: `GitRepositoryReader` reads worktrees, branches, and the remote's owner straight from `.git` files, which is quicker than running `git` on every refresh. `Git.run` runs `/usr/bin/git` for anything that writes. Glance doesn't create or delete worktrees and branches, or commit; agents and CLIs do that, and Glance picks the results up on refresh. Changes offers a prompt asking the agent to commit the files marked as viewed. `WorkingTreeReader` parses `git status` and `git diff HEAD` into each worktree's changes, and `FileWatcher` (FSEvents) re-reads them when files, the index or `HEAD` change; staging goes through `Git.run`. Clicking a sidebar branch previews `git diff <main>...<branch>` read-only; double-clicking checks it out. `RepositoryBookmarks` (in `State/`) keeps those folders across launches. `AvatarStore` (in `State/`) fetches owner avatars from the remote's host API (GitHub, GitLab, Bitbucket, Gitea/Forgejo) and caches them in `~/Library/Caches/<bundle id>` for a week. `RemoteDetailsStore` asks the same hosts whether a repository is private or a fork, cached for a day; anything the host hides from anonymous requests (401/403/404) counts as private. Both go through `Git/HostAPI`.
- `Models/`: plain value types (`FileDiff`, `Commit`, `Worktree`, `FileNode`). `RawHunk` lines use `+`/`-`/space prefixes.
- `SampleData/`: all static content. Replace it with a git-backed source later.
- `Syntax/`: `SyntaxHighlighter` parses with tree-sitter (SPM grammar packages) and maps captures onto `SyntaxToken`s. `FileDiff` highlights each hunk's old and new sides when it's built. `Views/Components/SyntaxStyle.swift` turns spans into `Palette.syntax*` colors. JavaScript is pinned to 0.23.1 and YAML to 0.7.0, because their newer manifests drop `scanner.c` when built as dependencies.
- `State/`: `@Observable` models. `AppModel` owns one `ChangesModel` per worktree plus `HistoryModel` and `FilesModel`. Single-key shortcuts (J/K/V, arrows, ⌥S) go through `KeyboardShortcutMonitor`, which ignores keys while a text field is being edited.
- `Views/`: Sidebar, Changes, History, Files, and the ⌘K Switcher, plus shared `Components/`.

## Conventions

- Use `Palette` tokens rather than raw colors; use the accent from `@Environment(\.glanceAccent)`.
- Diff rows live in one `LazyVStack` with pinned hunk headers, so row IDs must be unique across hunks and across the unified and split layouts.
