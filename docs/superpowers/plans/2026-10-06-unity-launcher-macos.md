# Unity Launcher macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native SwiftUI macOS app tương đương UnityLauncherPro, dùng Unity CLI làm lõi.

**Architecture:** Views → `AppState` (@Observable, MainActor) → `UnityCLI` (Process + JSON envelope) / `Local` (git, ps, folders). Một executable target SPM, không phụ thuộc ngoài.

**Tech Stack:** Swift 6.4, SwiftUI (macOS 14+), Swift Testing, SPM.

**Spec:** `docs/superpowers/specs/2026-10-06-unity-launcher-macos-design.md`

## Global Constraints

- macOS 14+, `swift-tools-version:6.0`, không dependency ngoài.
- Mọi lệnh test/build: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (xcode-select trỏ CLT — không đổi cài đặt hệ thống).
- Gọi CLI: `unity --no-banner --non-interactive --format json|ndjson <args>`, env `UNITY_NO_CONSENT_PROMPT=1 UNITY_NO_UPDATE_CHECK=1 UNITY_NO_PAGER=1`. Args luôn truyền dạng mảng, không qua shell.
- Không parse stderr để quyết định thành công; chỉ dùng `success` trong envelope.
- Thao tác phá huỷ (kill, uninstall, clean, remove) luôn confirm.

## Review Focus

1. Path có dấu cách / Unicode (`~/Work/My Game ✨`) → phải tới CLI nguyên vẹn. Test: fake CLI echo args (Task 2).
2. Stdout có dòng rác trước JSON (notice) → vẫn decode được từ `{` đầu tiên. Test (Task 2).
3. Version rỗng / lạ (`""`, `2019.4.40f1c1`) → `UnityVersion` trả nil hoặc parse lỏng, không crash; sort đưa nil xuống cuối. Test (Task 1).
4. Process chết giữa stream ndjson không có frame `result` → task kết thúc lỗi với exit code. Test (Task 2).
5. Git worktree / submodule (`.git` là file `gitdir: …`) → vẫn đọc được branch. Test (Task 3).

---

### Task 1: Package + Models

**Files:** Create `Package.swift`, `Sources/UnityLauncher/Models.swift`, `Sources/UnityLauncher/App.swift` (stub), `Tests/UnityLauncherTests/ModelsTests.swift`, `Tests/UnityLauncherTests/Fixtures/{projects,editors,releases,error}.json`

**Produces:**
- `struct Envelope<T: Decodable>: Decodable { success: Bool; data: T?; errors: [CLIErrorItem]; warnings: [String] }`, `struct CLIErrorItem: Decodable { code: String; message: String }`
- `struct Project: Decodable, Identifiable, Hashable { id = path; title, path, version: String; architecture, buildTarget, renderPipeline, vcsProvider: String?; lastModified: Double?; isFavorite: Bool? }` + `var modified: Date?`
- `struct EditorInstall: Decodable, Identifiable, Hashable { id = location; version, architecture, location, modules: String; isDefault: Bool (key "default") }`
- `struct Release: Decodable, Identifiable, Hashable { id = version+arch; version, architecture, stream: String; lts, installed: Bool }`
- `struct UnityVersion: Comparable { major, minor, patch: Int; type: Character; build: Int; init?(_ s: String) }`; `static func suggestUpgrade(from: String, installed: [String]) -> String?` (nhỏ nhất > from)

- [ ] Step 1: Viết test: decode 3 fixture (đếm phần tử, field mẫu), fixture lỗi → `success == false`, `errors[0].code`; `UnityVersion("6000.3.16f1") > UnityVersion("2022.3.62f3")`, `"2022.3.10f1" < "2022.3.10p1"`, `a < b < f`, `UnityVersion("") == nil`, `UnityVersion("2019.4.40f1c1")` parse được (bỏ hậu tố), `suggestUpgrade(from:"2022.3.62f3", installed:["6000.3.16f1","2021.3.1f1"]) == "6000.3.16f1"`.
- [ ] Step 2: `swift test` → FAIL (chưa có type).
- [ ] Step 3: Viết `Package.swift` (executableTarget `UnityLauncher`, testTarget với `resources: [.copy("Fixtures")]`), Models, App stub.
- [ ] Step 4: `swift test` → PASS.
- [ ] Step 5: Commit `feat: models and CLI envelope`.

### Task 2: UnityCLI runner

**Files:** Create `Sources/UnityLauncher/UnityCLI.swift`, `Tests/UnityLauncherTests/UnityCLITests.swift`

**Consumes:** `Envelope`, `CLIErrorItem`.
**Produces:**
- `enum CLIError: LocalizedError { notFound; failed(code: String, message: String); badOutput(String); exited(Int32) }`
- `struct UnityCLI: Sendable { let executable: URL; static func locate(override: String?) -> URL?; func run<T: Decodable>(_ args: [String], as: T.Type) async throws -> T; func runVoid(_ args: [String]) async throws; func stream(_ args: [String]) -> AsyncThrowingStream<Frame, Error>; func spawn(_ args: [String]) throws -> Process }`
- `struct Frame: Decodable { type: String; message: String?; pct: Double?; success: Bool?; errors: [CLIErrorItem]? }`
- `static func decodeEnvelope<T>(_ data: Data) throws -> T` (cắt từ `{` đầu tiên)

- [ ] Step 1: Test với fake binary (script `#!/bin/sh` ghi vào thư mục tạm, chmod 755):
  - echo args mỗi dòng → `run([..."My Game ✨"])` nhận đúng args, có `--no-banner --non-interactive --format json`, env `UNITY_NO_PAGER` được set.
  - in `notice\n{"success":true,"data":[1],"errors":[],"warnings":[]}` → `[Int]` = `[1]`.
  - in envelope `success:false` + exit 6 → throw `.failed(code:"X", …)`.
  - stdout rỗng + exit 1 → throw `.exited(1)`.
  - stream: in 2 frame progress + frame result → nhận 3 frame; script in 1 progress rồi `exit 6` → stream throw `.exited(6)`.
- [ ] Step 2: `swift test` → FAIL.
- [ ] Step 3: Implement. `Process` với `executableURL`, `arguments`, `environment = ProcessInfo.env + 3 biến`; đọc stdout bằng `readDataToEndOfFile` trên background (`Task.detached`), chờ `waitUntilExit`. Stream: đọc theo dòng bằng `FileHandle.bytes.lines`.
- [ ] Step 4: `swift test` → PASS.
- [ ] Step 5: Commit `feat: Unity CLI runner`.

### Task 3: Local helpers

**Files:** Create `Sources/UnityLauncher/Local.swift`, `Tests/UnityLauncherTests/LocalTests.swift`

**Produces (enum `Local`):**
- `static func gitBranch(at project: URL) -> String?` — đi lên tối đa 4 cấp tìm `.git`; nếu là file `gitdir: X` thì theo; đọc `HEAD`: `ref: refs/heads/B` → `B`, ngược lại 7 ký tự đầu hash.
- `static func parseUnityProcesses(_ psOutput: String) -> [(pid: Int32, projectPath: String)]` — dòng chứa `Unity.app/Contents/MacOS/Unity`, lấy giá trị sau `-projectpath` (không phân biệt hoa thường, path có dấu cách tới flag `-` kế tiếp hoặc hết dòng).
- `static func runningUnity() -> [(pid: Int32, projectPath: String)]` (chạy `/bin/ps -axo pid=,command=`).
- `static func kill(pid: Int32)` (`SIGKILL`).
- `static func playerSettings(at project: URL) -> (company: String, product: String)?` đọc `companyName:` / `productName:` trong `ProjectSettings/ProjectSettings.asset`.
- `enum Folder: CaseIterable { editorLogs, crashLogs, hubLogs, assetStore, unityCache, giCache; var url: URL }` (`~/Library/Logs/Unity`, `~/Library/Logs/DiagnosticReports`, `~/Library/Application Support/UnityHub/logs`, `~/Library/Unity/Asset Store-5.x`, `~/Library/Unity/cache`, `~/Library/Caches/com.unity3d.UnityEditor/GiCache`).
- `static func persistentDataURL(company:product:) -> URL` = `~/Library/Application Support/<company>/<product>`; `playerLogURL` = `~/Library/Logs/<company>/<product>/Player.log`.
- `enum ProjectPrefs { static func args(for path: String) -> String; static func setArgs(_: String, for: String) }` (UserDefaults key `args:<path>`).

- [ ] Step 1: Test: branch (ref, detached hash, thư mục con 2 cấp, worktree `.git` file), parse ps (path có dấu cách, `-projectPath` hoa thường lẫn lộn, dòng không phải Unity bị bỏ), playerSettings từ asset mẫu.
- [ ] Step 2: FAIL. Step 3: implement. Step 4: PASS.
- [ ] Step 5: Commit `feat: local helpers (git, processes, folders)`.

### Task 4: AppState + Projects tab + app shell

**Files:** Create `AppState.swift`, `ProjectsView.swift`; Modify `App.swift`

**Consumes:** Task 1–3.
**Produces:** `@MainActor @Observable final class AppState { projects: [ProjectRow]; editors: [EditorInstall]; releases: [Release]; search: String; error: String?; cli: UnityCLI?; tasks: [TaskItem]; func refresh() async; func open(_ p: ProjectRow, version: String? = nil); func perform(_ title: String, _ op: () async throws -> Void) }`; `struct ProjectRow: Identifiable { project: Project; exists: Bool; branch: String?; pid: Int32? }`; `var filteredProjects` (search tên+path, pinned trước, rồi modified giảm dần; ẩn missing nếu setting tắt).

- Projects `Table`: Name, Version (đỏ nếu chưa cài), Branch, Platform, SRP, Modified (relative), Path. Double-click / ⏎ → open. Toolbar: Refresh, Add (NSOpenPanel chọn folder → `projects add`), New (Task 5), search `.searchable`.
- Context menu: Open, Open With ▸ (editors đã cài), Arguments…, Reveal in Finder, Open in Terminal, Copy Path, Copy Version, Edit manifest.json, Pin/Unpin, Kill Unity (nếu pid, confirm, ⌥Q), Remove from List (confirm).
- Open khi thiếu editor → alert: "Install <v>" (Task 5 task) / "Open with…".
- Banner khi `cli == nil`: lệnh cài + nút Copy + nút Settings.

- [ ] Step 1: Test `filteredProjects` (search khớp path, pinned lên đầu, missing ẩn) với AppState nạp tay.
- [ ] Step 2–4: FAIL → implement → PASS; `swift build` và chạy `.build/debug/UnityLauncher`, xác nhận 3 project thật hiện ra.
- [ ] Step 5: Commit `feat: projects tab`.

### Task 5: Long-running tasks + project deep actions

**Files:** Create `TasksView.swift`, `NewProjectSheet.swift`, `ProjectActions.swift` (sheets: Upgrade, Build, Arguments); Modify `AppState.swift`, `ProjectsView.swift`

**Produces:** `@Observable final class TaskItem: Identifiable { title: String; log: [String]; pct: Double?; state: running|succeeded|failed(String); process: Process? ; func stop() }`; `AppState.runTask(_ title: String, _ args: [String])` (stream) và `AppState.runServer(_ title:, _ args:)` (spawn, giữ process).

Hành động: New Project (`templates list --editor v --type core` → `projects new NAME --path P --editor-version v --template id`, mở sau khi tạo nếu bật), Upgrade (gợi ý `suggestUpgrade` → `projects upgrade PATH --to v --yes`), Build (target picker StandaloneOSX/iOS/Android/WebGL, output `Builds/<target>` → `build PATH --target T --output-path O`), Run Tests (`test PATH --mode EditMode --output <tmp>/results.xml`), Run WebGL Build (`build run PATH --path PATH/Builds/WebGL` spawn), Size (`projects size PATH` → alert), Clean Library (confirm → `projects clean PATH --yes`), Verify (`projects verify PATH` → alert tóm tắt), Install missing editor (`install v --yes --accept-eula`). Player log / Persistent data (Task 3 helpers).

- [ ] Step 1: Test `TaskItem` cập nhật từ frame (pct, log, state failed khi result `success:false`) dùng fake CLI Task 2.
- [ ] Step 2–4: FAIL → implement → PASS; chạy app, thử Size + Verify trên project thật.
- [ ] Step 5: Commit `feat: long-running tasks and project actions`.

### Task 6: Editors + Releases tabs

**Files:** Create `EditorsView.swift`, `ReleasesView.swift`; Modify `AppState.swift`

- Editors Table: Version, Arch, Modules, Default (★), Path. Context: Run Unity (open `Unity.app`), Reveal, Copy Path, Release Notes (`https://unity.com/releases/editor/whats-new/<major.minor.patch>`), Set Default (`editors default v`), Modules… (sheet: `editors module list v` checkbox → task `editors module add v --module a --module b --accept-eula`), Upgrade Patch (task `editors upgrade v --yes --accept-eula`), Uninstall (confirm → task `uninstall v --architecture a --yes`). Toolbar: Locate editor (NSOpenPanel `.app` → `editors add PATH`).
- Releases Table: Version, Stream, LTS, Installed. Picker stream (All/LTS/Tech/Beta/Alpha → `releases --limit 200 [--stream s]`), search, Install (task), Release Notes, Copy Version. Tải lười khi chọn tab.
- `ModuleInfo` decode lỏng: `struct ModuleInfo: Decodable { id: String; name: String?; installed: Bool? }` — xác minh bằng chạy thật `unity modules list 6000.3.16f1 --format json` trước khi viết.

- [ ] Step 1: Test release notes URL (`6000.3.16f1` → `.../6000.3.16`), filter releases theo search.
- [ ] Step 2–4: FAIL → implement → PASS; chạy app, mở tab Editors/Releases với dữ liệu thật.
- [ ] Step 5: Commit `feat: editors and releases tabs`.

### Task 7: Menu bar, Tools menu, Settings, Finder integration, bundle

**Files:** Create `MenuBarView.swift`, `SettingsView.swift`, `scripts/bundle.sh`, `README.md`; Modify `App.swift`

- `MenuBarExtra("Unity", systemImage: "cube")`: 10 project gần nhất (click → open), Show Launcher, Quit.
- `Commands`: menu Tools: các `Local.Folder`, ADB Logcat (Terminal `adb logcat -s Unity` qua `osascript`), Unity Doctor (`doctor` → alert JSON rút gọn), Refresh ⌘R.
- Settings (`@AppStorage`): CLI path override, show missing projects, close (hide) after open, default new-project folder, launch at login (`SMAppService.mainApp` — chỉ hoạt động khi chạy từ `.app`).
- `NSApplicationDelegateAdaptor`: `application(_:open urls:)` → folder có `ProjectSettings/ProjectVersion.txt` → open; `NSServices` provider `openProject(_:userData:error:)` đọc `NSPasteboard` file URL.
- `bundle.sh`: `swift build -c release` → `build/UnityLauncher.app/Contents/{MacOS,Info.plist}`; Info.plist: `CFBundleIdentifier=dev.kai.UnityLauncher`, `LSMinimumSystemVersion=14.0`, `CFBundleDocumentTypes` (public.folder, Viewer), `NSServices` (menu "Open in Unity Launcher", `NSSendFileTypes` public.folder); ad-hoc `codesign -s -`.
- README: build, chạy, Finder integration, yêu cầu Unity CLI.

- [ ] Step 1: `scripts/bundle.sh` → `open build/UnityLauncher.app`; kiểm tra menu bar, Tools, Settings; `open -a build/UnityLauncher.app <project>` mở project.
- [ ] Step 2: `swift test` toàn bộ PASS.
- [ ] Step 3: Commit `feat: menu bar, tools, settings, Finder integration, bundling`.
