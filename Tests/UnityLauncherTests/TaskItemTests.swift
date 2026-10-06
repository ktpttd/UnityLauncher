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

@MainActor @Test func loadsBuildProfilesFromCLI() async throws {
    let state = AppState(cli: try fakeCLI(#"echo '{"success":true,"data":[{"profile":"iOS","path":"Assets/Settings/Build Profiles/iOS.asset"}],"errors":[],"warnings":[]}'"#))
    let profiles = await state.buildProfiles(project: "/p")
    #expect(profiles == [BuildProfile(profile: "iOS", path: "Assets/Settings/Build Profiles/iOS.asset")])
}

/// `unity build` progress frames use "msg", not "message" (seen on a real iOS build).
@MainActor @Test func buildProgressFramesUseMsgKey() {
    let item = TaskItem(title: "Build")
    item.apply(frame(#"{"type":"progress","pct":0,"msg":"Starting build (iOS)..."}"#))
    item.apply(frame(#"{"type":"progress","pct":100,"msg":"Build complete"}"#))
    #expect(item.log == ["Starting build (iOS)...", "Build complete"])
    #expect(item.pct == 100)
}
