import Foundation
import Testing
@testable import UnityLauncher

func frame(_ json: String) -> Frame { try! JSONDecoder().decode(Frame.self, from: Data(json.utf8)) }

@MainActor @Test func progressFramesUpdateLogAndPercent() {
    let item = TaskItem(title: "Install")
    item.apply(frame(#"{"type":"progress","message":"Downloading","pct":12.5}"#))
    item.apply(frame(#"{"type":"progress","pct":40}"#))
    #expect(item.log == ["Downloading"])
    #expect(item.pct == 40)
    #expect(item.state == .running)
}

@MainActor @Test func resultFrameSetsFinalState() {
    let ok = TaskItem(title: "a")
    ok.apply(frame(#"{"type":"result","success":true,"errors":[]}"#))
    #expect(ok.state == .succeeded)

    let bad = TaskItem(title: "b")
    bad.apply(frame(#"{"type":"result","success":false,"errors":[{"code":"E","message":"Editor missing"}]}"#))
    #expect(bad.state == .failed("Editor missing"))
}

@MainActor @Test func runTaskStreamsFakeCLIToCompletion() async throws {
    let cli = try fakeCLI(#"""
    echo '{"type":"progress","message":"Step 1"}'
    echo '{"type":"result","success":true,"errors":[]}'
    """#)
    let state = AppState(cli: cli)
    let item = state.runTask("Build", ["build", "/p"], refreshAfter: false)
    await item.task?.value
    #expect(state.tasks.first === item)
    #expect(item.log == ["Step 1"])
    #expect(item.state == .succeeded)
}

@MainActor @Test func runTaskFailsWhenProcessDiesWithoutResult() async throws {
    let state = AppState(cli: try fakeCLI("exit 6"))
    let item = state.runTask("Install", ["install", "x"], refreshAfter: false)
    await item.task?.value
    guard case .failed = item.state else { Issue.record("expected failure, got \(item.state)"); return }
}

@MainActor @Test func stopCancelsRunningTask() async throws {
    let state = AppState(cli: try fakeCLI("echo '{\"type\":\"progress\",\"message\":\"go\"}'; sleep 30"))
    let item = state.runTask("Long", ["test", "/p"], refreshAfter: false)
    try await Task.sleep(for: .milliseconds(300))
    item.stop()
    await item.task?.value
    #expect(item.state == .failed("Stopped"))
}

@MainActor @Test func findingFramesAreLogged() {
    let item = TaskItem(title: "Verify")
    item.apply(frame(#"{"type":"finding","code":"META_MISSING","severity":"error","path":"Assets/a.png"}"#))
    item.apply(frame(#"{"type":"finding","code":"CONFLICT_MARKERS","severity":"error","path":"Assets/b.meta","message":"Has conflict markers."}"#))
    #expect(item.log == ["error META_MISSING Assets/a.png", "error CONFLICT_MARKERS Assets/b.meta: Has conflict markers."])
}

@Test func sizeSummaryListsLargestFolders() throws {
    let size = try JSONDecoder().decode(ProjectSize.self, from: Data(#"""
    {"path":"/p","total":3000000,"breakdown":[{"folder":"Library","bytes":2000000},{"folder":"Assets","bytes":1000000}]}
    """#.utf8))
    let lines = size.summary.split(separator: "\n")
    #expect(lines.count == 3)
    #expect(lines[0].hasPrefix("Total"))
    #expect(lines[1].hasPrefix("Library"))
}

@Test func defaultBuildOutputPerTarget() {
    #expect(BuildTarget.macOS.defaultOutput(project: "/p", product: "Game") == "/p/Builds/StandaloneOSX/Game.app")
    #expect(BuildTarget.windows.defaultOutput(project: "/p", product: "Game") == "/p/Builds/StandaloneWindows64/Game.exe")
    #expect(BuildTarget.linux.defaultOutput(project: "/p", product: "Game") == "/p/Builds/StandaloneLinux64/Game.x86_64")
    #expect(BuildTarget.iOS.defaultOutput(project: "/p", product: "Game") == "/p/Builds/iOS")
    #expect(BuildTarget.android.defaultOutput(project: "/p", product: "Game") == "/p/Builds/Android/Game.apk")
    #expect(BuildTarget.webGL.defaultOutput(project: "/p", product: "Game") == "/p/Builds/WebGL")
}

/// Product names like "Eggoo : Roguelike" must not put ':' or '/' into file names.
@Test func buildOutputSanitizesProductName() {
    #expect(BuildTarget.macOS.defaultOutput(project: "/p", product: "Eggoo : Rogue/like") == "/p/Builds/StandaloneOSX/Eggoo - Rogue-like.app")
}

@Test func onlyDesktopTargetsBuildWithoutProfile() {
    #expect(BuildTarget.allCases.filter { !$0.needsProfile } == [.macOS, .windows, .linux])
}

@Test func buildArgumentsUseTargetOrProfile() {
    #expect(BuildTarget.arguments(project: "/p", target: .macOS, profile: nil, output: "/o", allowDirty: false)
            == ["build", "/p", "--output-path", "/o", "--target", "StandaloneOSX"])
    #expect(BuildTarget.arguments(project: "/p", target: .iOS, profile: "Assets/Settings/Build Profiles/iOS.asset", output: "/o", allowDirty: true)
            == ["build", "/p", "--output-path", "/o", "--profile", "Assets/Settings/Build Profiles/iOS.asset", "--allow-dirty-build"])
}

func profileAsset(name: String, target: Int) -> String {
    """
    %YAML 1.1
    --- !u!114 &11400000
    MonoBehaviour:
      m_Script: {fileID: 15003, guid: 0000000000000000e000000000000000, type: 0}
      m_Name: \(name)
      m_EditorClassIdentifier: UnityEditor.dll::UnityEditor.Build.Profile.BuildProfile
      m_AssetVersion: 1
      m_BuildTarget: \(target)
    """
}

/// `unity build --list-profiles` only scans "Assets/Settings/Build Profiles"; real projects keep them elsewhere.
@Test func scansBuildProfilesAnywhereInAssets() throws {
    let project = try unityProject()
    try write(profileAsset(name: "iOS_DEV", target: 9), to: project.appendingPathComponent("Assets/Settings/BuildProfiles/iOS_DEV.asset"))
    try write(profileAsset(name: "Android", target: 13), to: project.appendingPathComponent("Assets/Settings/Build Profiles/Android.asset"))
    try write(profileAsset(name: "Quest", target: 999), to: project.appendingPathComponent("Assets/XR/Quest.asset"))
    try write("%YAML 1.1\nMonoBehaviour:\n  m_Name: Settings\n  m_EditorClassIdentifier: Game::Settings\n",
              to: project.appendingPathComponent("Assets/Settings/GameSettings.asset"))
    let profiles = Local.buildProfiles(in: project)
    #expect(profiles.map(\.profile) == ["Android", "iOS_DEV", "Quest"])
    #expect(profiles.map(\.path) == ["Assets/Settings/Build Profiles/Android.asset", "Assets/Settings/BuildProfiles/iOS_DEV.asset", "Assets/XR/Quest.asset"])
    #expect(profiles.map(\.target) == [.android, .iOS, nil])
}

@Test func mapsUnityBuildTargetIDs() {
    #expect([2, 9, 13, 19, 20, 24, 5].map(BuildTarget.init(unityID:)) == [.macOS, .iOS, .android, .windows, .webGL, .linux, nil])
}

/// `unity build` progress frames use "msg", not "message" (seen on a real iOS build).
@MainActor @Test func buildProgressFramesUseMsgKey() {
    let item = TaskItem(title: "Build")
    item.apply(frame(#"{"type":"progress","pct":0,"msg":"Starting build (iOS)..."}"#))
    item.apply(frame(#"{"type":"progress","pct":100,"msg":"Build complete"}"#))
    #expect(item.log == ["Starting build (iOS)...", "Build complete"])
    #expect(item.pct == 100)
}

/// Profiles saved by older Unity 6 versions leave m_EditorClassIdentifier empty (seen in a real project).
@Test func detectsProfilesWithEmptyClassIdentifier() throws {
    let project = try unityProject()
    try write("""
    %YAML 1.1
    --- !u!114 &11400000
    MonoBehaviour:
      m_Script: {fileID: 15003, guid: 0000000000000000e000000000000000, type: 0}
      m_Name: iOS_DEV
      m_EditorClassIdentifier: 
      m_AssetVersion: 1
      m_BuildTarget: 9
    """, to: project.appendingPathComponent("Assets/Settings/BuildProfiles/iOS_DEV.asset"))
    #expect(Local.buildProfiles(in: project).map(\.profile) == ["iOS_DEV"])
}
