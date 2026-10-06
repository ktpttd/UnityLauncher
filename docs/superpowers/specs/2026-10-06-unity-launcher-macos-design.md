# Unity Launcher for macOS — Design

Ngày: 2026-10-06 · Tham khảo: https://github.com/unitycoder/UnityLauncherPro (ULP, Windows/WPF)

## Mục tiêu

App macOS native thay thế Unity Hub cho việc hằng ngày, tính năng tương đương ULP, dùng **Unity CLI** (`unity`, 1.0.0-beta) làm lõi xử lý.

Thành công khi:
- Mở project đúng version trong ≤ 1 giây từ lúc click (thời gian của app, không tính Unity khởi động).
- Mọi thao tác ULP có trên macOS đều làm được từ app (bảng đối chiếu bên dưới).
- CLI lỗi / không cài / project mất folder → thông báo rõ, không crash.

## Quyết định chính

| Quyết định | Chọn | Lý do |
|---|---|---|
| UI | SwiftUI, macOS 14+ | Native, có `Table`, `MenuBarExtra`, `@Observable` |
| Build | Swift Package Manager + `scripts/bundle.sh` → `.app` | Không có `.pbxproj`, diff sạch, vẫn mở được bằng Xcode |
| Nguồn dữ liệu | `unity … --format json` | CLI đã gộp Hub registry + recent của Editor, cài editor, templates, upgrade, build… — không tự viết lại |
| Phụ thuộc ngoài | Không | Foundation `Process`, `JSONDecoder`, `NSWorkspace` đủ dùng |
| Phát hiện Unity đang chạy | Parse `ps -axo pid=,command=` | `unity editors running` chưa có schema JSON được tài liệu hoá; `ps` ổn định và test được |

## Kiến trúc

```
View (SwiftUI) ──▶ AppState (@Observable, @MainActor) ──▶ UnityCLI ──▶ Process("unity" …)
                                    │                         └─ Envelope<T> decode
                                    └──▶ Local (git branch, ps, log folders, per-project args)
```

```
Package.swift
Sources/UnityLauncher/
  App.swift            @main: Window(tabs) + MenuBarExtra + Settings + Commands(Tools); AppDelegate (mở folder từ Finder/Dock, Services)
  UnityCLI.swift       tìm binary, run → Envelope<T>, stream ndjson (task dài), chạy detached
  Models.swift         Project, EditorInstall, Release, Template, UnityVersion(Comparable)
  Local.swift          gitBranch(), runningUnity() parse ps, kill, log folders, ProjectPrefs (args tuỳ chỉnh)
  AppState.swift       load/refresh, filter/search, actions, danh sách Task đang chạy + log
  ProjectsView.swift   Table + toolbar + context menu
  EditorsView.swift    Table editor + module sheet
  ReleasesView.swift   Table release + filter stream + install
  NewProjectSheet.swift  tên, thư mục cha, version, template
  TasksView.swift      task dài (install/build/test/webgl): progress, log, stop
  SettingsView.swift
  MenuBarView.swift
Tests/UnityLauncherTests/   Swift Testing
scripts/bundle.sh
```

### UnityCLI

- Tìm binary theo thứ tự: Settings override → `~/.unity/bin/unity` → `/opt/homebrew/bin/unity` → `/usr/local/bin/unity`. App GUI không thừa hưởng PATH của shell nên không dựa vào `PATH`.
- Mọi lệnh: `unity --no-banner --non-interactive --format json <args…>`; env `UNITY_NO_CONSENT_PROMPT=1 UNITY_NO_UPDATE_CHECK=1 UNITY_NO_PAGER=1`.
- `run<T: Decodable>(args) async throws -> T`: đọc stdout, decode `Envelope<T> { success, data, errors[{code,message}], warnings }`. `success == false` → throw `CLIError.failed(code, message)`. Không parse stderr (theo tài liệu CLI); stdout rỗng + exit ≠ 0 → throw kèm stderr để debug.
- `stream(args) -> AsyncThrowingStream<Frame>`: dùng `--format ndjson`, mỗi dòng là `{"type":"progress"|"result", message?, pct?, …}`. Dùng cho install, upgrade, build, test.
- `launchDetached(args)`: cho `open` (CLI trả về ngay sau khi giao cho Editor) và `build run` (server WebGL sống lâu — giữ `Process` để Stop).

### Models (khớp JSON thật của CLI 1.0.0-beta.11)

- `Project`: `title, path, version, architecture?, lastModified(ms), isFavorite, buildTarget?, renderPipeline?, vcsProvider?` + local: `exists`, `branch`, `isRunning`.
- `EditorInstall`: `version, architecture, location, modules(String), default`.
- `Release`: `version, architecture, stream(ALPHA|BETA|TECH|LTS…), lts, installed`.
- `UnityVersion`: parse `6000.3.16f1` → (major, minor, patch, type a<b<f<p, build); `Comparable`. Dùng để sort, gợi ý version upgrade (version đã cài kế tiếp cao hơn — như ULP).

## Tính năng — đối chiếu ULP

| ULP | App macOS | Cách làm |
|---|---|---|
| Recent projects + version + modified | Tab Projects | `projects list` |
| Mở đúng version | Double-click / ⏎ | `open <path>` (+ `--args` tuỳ chỉnh) |
| Thiếu version → download | Alert "Cài version X?" | stream `install <v> --yes --accept-eula` |
| Show missing projects | Toggle Settings, hàng mờ | `FileManager.fileExists` |
| Git branch | Cột Branch | đọc `.git/HEAD` (đi lên thư mục cha) |
| Platform, SRP | Cột | `buildTarget`, `renderPipeline` từ CLI |
| Search (tên + path) | Ô search | filter local |
| Add project | Toolbar / kéo thả folder | `projects add` |
| Remove from list | Context menu | `projects remove` |
| Pin/favorite | Context menu, pinned lên đầu | `projects pin/unpin` |
| New project + template | Sheet | `templates list --editor v`, `projects new … --path --editor-version --template` |
| Upgrade project | Sheet chọn version (gợi ý version kế) | stream `projects upgrade <path> --to v --yes` |
| Custom launch args | Context menu "Arguments…" | UserDefaults theo path → `open --args` |
| Explore folder, copy path/version | Context menu | `NSWorkspace`, `NSPasteboard` |
| Open in Terminal | Context menu | `open -a Terminal <path>` |
| Edit packages | Context menu | mở `Packages/manifest.json` |
| Kill Unity process (⌥Q) | Context menu + ⌥Q | `kill(pid, SIGKILL)` sau confirm |
| Editor.log, Player log, Crash logs, Hub logs, Asset Store, Unity cache, GI cache | Menu Tools + context menu | mở folder cố định trong `~/Library/…` |
| PersistentDataPath / Player log | Context menu | `~/Library/Application Support/<company>/<product>` (đọc `ProjectSettings.asset`) |
| WebGL server | Context menu "Run WebGL Build" | `build run <path> --path <Builds/WebGL…>` detached, Stop trong Tasks |
| Build | Context menu "Build…" (target + output) | stream `build <path> --target T --output-path …` |
| — (mới) Run tests | Context menu | stream `test <path> --mode EditMode` |
| — (mới) Project size / Clean Library / Verify | Context menu | `projects size`, `projects clean --yes`, `projects verify` |
| Installed editors | Tab Editors | `editors --installed` |
| Run Unity / Explore / Copy path / Release notes | Context menu | `NSWorkspace.open`, URL release notes |
| Set preferred version | Context menu | `editors default v` |
| Download modules | Sheet modules | `editors module list v`, stream `editors module add v --module …` |
| Uninstall | Context menu (confirm) | stream `uninstall v --yes` |
| — (mới) Upgrade patch | Context menu | stream `editors upgrade v --yes --accept-eula` |
| Updates / releases + stream filter | Tab Releases | `releases --limit 200` (+ `--stream`) |
| Download & Install | Nút Install | stream `install v --yes --accept-eula` |
| ADB logcat | Menu Tools | Terminal: `adb logcat -s Unity` (nếu có adb) |
| Explorer context menu | Finder: "Open With" / Services / kéo folder lên Dock icon | `CFBundleDocumentTypes` (folder) + `NSServices` |
| Commandline `-projectPath` | `UnityLauncher /path` hoặc `unity open /path` | AppDelegate nhận URL → `open` |
| Close after opening | Setting | `NSApp.hide` |
| Run at startup | Setting | `SMAppService.mainApp` |
| Minimize to tray | Menu bar extra | `MenuBarExtra` (10 project gần nhất) |
| Doctor | Menu Tools | `doctor` → hiển thị kết quả |

**Bỏ qua (Windows-only hoặc không cần):** theme editor (theo light/dark hệ thống), Defender exclusion, `.bat` shortcut, đăng ký APK, Plastic branch, streamer mode, auto-update, online templates GraphQL (CLI templates đã đủ), Build Report, patch Hub `editors.json`.

## Luồng dữ liệu

1. Khởi động → `AppState.refresh()` chạy song song `projects list`, `editors --installed`; releases tải lười khi mở tab.
2. Với mỗi project: `exists`, `branch` tính local (cheap, off main thread); `isRunning` từ một lần `ps`.
3. Hành động ngắn (open, pin, remove, default) → `run` → refresh phần liên quan.
4. Hành động dài → tạo `TaskItem` (title, progress, log lines, process) trong `AppState.tasks`; TasksView hiển thị; xong → refresh.

## Xử lý lỗi

- Không tìm thấy CLI → banner trên cửa sổ: hướng dẫn cài (hiện lệnh, nút Copy) + chọn đường dẫn trong Settings. Không tự chạy script cài.
- `CLIError.failed(code, message)` → alert với message của CLI.
- Decode thất bại → alert "Unexpected CLI output" + đoạn đầu stdout/stderr.
- Project mất folder → hàng mờ, chỉ cho phép Remove/Copy path.
- Thiếu editor version của project → hỏi cài (`install`) hoặc mở bằng version khác (`open --editor-version`).
- Thao tác phá huỷ (kill, uninstall, clean, remove) luôn confirm.

## Test

Swift Testing (`swift test`, cần `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` vì `xcode-select` đang trỏ CLT):
- Decode envelope từ fixture JSON thật (đã ẩn danh): projects, editors, releases, lỗi `success:false`.
- `UnityVersion` parse + so sánh + gợi ý upgrade.
- `gitBranch` trên thư mục tạm (HEAD ref, detached, thư mục con).
- Parse output `ps` → (pid, projectPath).
- `UnityCLI` với binary giả (script shell in JSON) → kiểm tra args/env và đường lỗi.
- Smoke: `scripts/bundle.sh` tạo `.app`, chạy app bằng tay, kiểm tra tab Projects hiện project thật.

## Ngoài phạm vi

Ký/notarize, auto-update, Windows/Linux, điều khiển Editor đang chạy qua `unity command` (có thể thêm sau).
