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
  - Upgrade, Build (macOS, Windows, Linux; iOS, Android, WebGL via a Unity 6 Build Profile, created from the sheet), Build Report (time, output size, largest assets of the last build), EditMode/PlayMode tests
  - Editor.log, Player.log, Persistent Data, the project's Logs folder
  - Disk usage, Verify (meta/GUID/merge-marker checks), Clean Library
  - Pin/Unpin, Kill Unity (⌥Q), Remove from list
- Android release builds: the Build sheet reads the keystore and alias from the chosen Build Profile (or Player Settings) and asks for the passwords. Passwords are passed to `unity build` for that build only and never saved.
- New Project (⌘N) with Unity version and template. Add a project with + or by dragging folders onto the list.

**Editors tab**
- Run, reveal, release notes, set default, add modules, upgrade to latest patch, uninstall, locate an editor installed elsewhere.

**Releases tab**
- All, LTS, Tech, Beta, and Alpha streams, with filter, install, and release notes.

**Live tab** (Unity 6+, needs the `com.unity.pipeline` package)
- Drive a running Editor through `unity command`: Play, Pause, Stop, Save All, Recompile, Screenshot.
- Live console with a log/warning/error filter.
- Run C# with `eval`, or send any of the Editor's commands from the command box (it suggests command names).
- For a project without the package, right-click it and choose **Enable Live Control…** to run `unity pipeline install`.

**Tasks panel (⇧⌘T)**
- Long operations (installs, builds, tests, upgrades, verify) stream progress and logs, and you can stop them.

**Tools tab**
- Editor, crash, and Hub logs; Asset Store downloads; Unity and GI caches
- Locate a Unity editor installed outside Unity Hub
- ADB logcat (uses Unity's bundled adb when available)
- Unity Doctor

**Menu bar**
- The 10 most recent projects, one click to open.

**Settings**
- Unity CLI path, show missing projects, hide after opening, default new-project folder, menu bar icon, launch at login.

## Opening projects from Finder or the command line

- Drag a project folder onto the Dock icon, or use **Open With → Unity Launcher**.
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
| `LiveEditor.swift` | Live tab model: `unity status` / `unity command` |
| `BuildReport.swift` | Parses Unity's Build Report from build logs |
| `*View.swift`, `*Sheet` | SwiftUI views |

## Credits

This app exists because of [UnityLauncherPro](https://github.com/unitycoder/UnityLauncherPro) by [unitycoder](https://github.com/unitycoder) (MIT license). Its feature set was the blueprint for this macOS version: recent projects with the right Unity version, per-project launch arguments, git branch and platform columns, editor and release lists, upgrade suggestions, log folders, Kill Unity, ADB logcat, the `-projectPath` command line, and the Build Report. The Build Report parser follows the Editor.log format UnityLauncherPro reads. The code here is a separate Swift implementation; nothing was copied from UnityLauncherPro.

If you're on Windows, use UnityLauncherPro.
