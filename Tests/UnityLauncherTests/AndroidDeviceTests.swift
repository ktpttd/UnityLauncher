import Foundation
import Testing
@testable import UnityLauncher

/// m_BuildAppBundle sits at the very end of a real profile (~45 KB in), past the header the scanner reads.
@Test func profileKnowsWhetherItBuildsAnAppBundle() throws {
    let project = try unityProject()
    let padding = String(repeating: "    - line: '|   someSetting: 0'\n", count: 300)
    try write(profileAsset(name: "Android_INTERNAL", target: 13) + "\n" + padding + "        m_BuildAppBundle: 1\n",
              to: project.appendingPathComponent("Assets/Settings/BuildProfiles/Android_INTERNAL.asset"))
    try write(profileAsset(name: "Android_DEV", target: 13) + "\n" + padding + "        m_BuildAppBundle: 0\n",
              to: project.appendingPathComponent("Assets/Settings/BuildProfiles/Android_DEV.asset"))
    let profiles = Local.buildProfiles(in: project)
    #expect(profiles.map(\.profile) == ["Android_DEV", "Android_INTERNAL"])
    #expect(profiles.map(\.appBundle) == [false, true])
}

@Test func appBundleBuildsGetAabExtension() {
    #expect(BuildTarget.android.defaultOutput(project: "/p", product: "Game", appBundle: true) == "/p/Builds/Android/Game.aab")
    #expect(BuildTarget.android.defaultOutput(project: "/p", product: "Game", appBundle: false) == "/p/Builds/Android/Game.apk")
}

@Test func parsesConnectedDevices() {
    let out = "List of devices attached\nR58M12ABC\tdevice\nemulator-5554\toffline\nZY22\tunauthorized\n\n"
    #expect(Android.devices(fromADBOutput: out) == ["R58M12ABC"])
    #expect(Android.devices(fromADBOutput: "List of devices attached\n\n").isEmpty)
}

@Test func parsesPackageFromBadging() {
    let badging = "package: name='com.silvertiger.eggoo' versionCode='1567' versionName='2.5.0'\nsdkVersion:'24'"
    #expect(Android.package(fromBadging: badging) == "com.silvertiger.eggoo")
    #expect(Android.package(fromBadging: "ERROR: dump failed") == nil)
}

@Test func picksNewestBuildTool() throws {
    let root = try tempDir()
    let app = root.appendingPathComponent("6000.3.16f1/Unity.app")
    for v in ["34.0.0", "36.0.0"] {
        let tool = root.appendingPathComponent("6000.3.16f1/PlaybackEngines/AndroidPlayer/SDK/build-tools/\(v)/aapt")
        try write("#!/bin/sh", to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
    }
    #expect(Android.buildTool("aapt", editorLocations: [app.path])?.path.contains("/36.0.0/aapt") == true)
}

@MainActor @Test func stepTasksReportFailureMessage() async {
    let state = AppState(cli: nil)
    let ok = state.runSteps("Install") { item in item.log.append("installed") }
    await ok.task?.value
    #expect(ok.state == .succeeded)
    struct Boom: LocalizedError { var errorDescription: String? { "No Android device connected." } }
    let bad = state.runSteps("Install") { _ in throw Boom() }
    await bad.task?.value
    #expect(bad.state == .failed("No Android device connected."))
}
