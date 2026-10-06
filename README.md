# Unity Launcher for macOS

A native SwiftUI launcher for Unity projects, modeled on [UnityLauncherPro](https://github.com/unitycoder/UnityLauncherPro) for Windows. The [Unity CLI](https://docs.unity.com) (`unity`) does the heavy lifting: project registry, editor installs, templates, upgrades, builds, and tests.

Not affiliated with Unity Technologies.

## Requirements

- macOS 14+
- Unity CLI. If it's missing, the app shows a banner with this install command:
  ```bash
  curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.sh | UNITY_CLI_CHANNEL=beta bash
  ```
- Xcode 16+ to build

## Build & run

```bash
./scripts/bundle.sh
```

```bash
open build/UnityLauncher.app
```

During development:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run
```

Tests (the second command also calls the real Unity CLI):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

```bash
UNITY_INTEGRATION=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Features

**Projects tab**
- Recent projects with version, git branch, platform, render pipeline, last modified, and path.
- Pinned projects sort first. Running projects show a green dot. Projects with a missing folder are dimmed and can be hidden in Settings.
- Double-click or ⏎ opens a project with its own Unity version. If that version isn't installed, the app offers to install it or open with another version.
- Context menu:
  - Open With, per-project launch arguments, Reveal in Finder, Open in Terminal, Edit `manifest.json`
  - Upgrade, Build (desktop targets or a Build Profile), Run WebGL Build (local server), EditMode/PlayMode tests
  - Editor.log, Player.log, Persistent Data, the project's Logs folder
  - Disk usage, Verify (meta/GUID/merge-marker checks), Clean Library
  - Pin/Unpin, Kill Unity (⌥Q), Remove from list
- New Project (⌘N) with Unity version and template. Add a project with + or by dragging folders onto the list.

**Editors tab**
- Run, reveal, release notes, set default, add modules, upgrade to latest patch, uninstall, locate an editor installed elsewhere.

**Releases tab**
- All, LTS, Tech, Beta, and Alpha streams, with filter, install, and release notes.

**Tasks panel (⇧⌘T)**
- Long operations (installs, builds, tests, upgrades, verify) stream progress and logs, and you can stop them.

**Tools menu**
- Editor, crash, and Hub logs; Asset Store downloads; Unity and GI caches
- ADB logcat (uses Unity's bundled adb when available)
- Unity Doctor

**Menu bar**
- The 10 most recent projects, one click to open.

**Settings**
- Unity CLI path, show missing projects, hide after opening, default new-project folder, menu bar icon, launch at login.

## Opening projects from Finder or the command line

- Drag a project folder onto the Dock icon, or use **Open With → Unity Launcher**.
- Right-click a folder and choose **Services → Open in Unity Launcher**.
- From the command line (`-projectPath` matches UnityLauncherPro):
  ```bash
  open -a build/UnityLauncher.app ~/Work/MyGame
  ```
  ```bash
  build/UnityLauncher.app/Contents/MacOS/UnityLauncher -projectPath ~/Work/MyGame
  ```
  You can also call the CLI directly:
  ```bash
  unity open ~/Work/MyGame
  ```

The app only opens folders that contain `ProjectSettings/ProjectVersion.txt`.

## Layout

| File | Role |
|---|---|
| `UnityCLI.swift` | Runs `unity --format json/ndjson`, decodes the `{success,data,errors}` envelope, streams progress |
| `Local.swift` | Git branch, running editors (`ps`), well-known folders, adb, per-project args |
| `AppState.swift` | Observable store and project actions |
| `Tasks.swift` | Long-running task model |
| `*View.swift`, `*Sheet` | SwiftUI views |
