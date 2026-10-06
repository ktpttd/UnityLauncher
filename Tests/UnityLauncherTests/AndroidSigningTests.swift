import Foundation
import Testing
@testable import UnityLauncher

func playerSettingsAsset(keystore: String, alias: String, custom: Int) -> String {
    """
    PlayerSettings:
      companyName: Co
      productName: Game
      AndroidKeystoreName: '\(keystore)'
      AndroidKeyaliasName: \(alias)
      androidUseCustomKeystore: \(custom)
    """
}

@Test func readsSigningFromPlayerSettings() throws {
    let project = try unityProject()
    try write(playerSettingsAsset(keystore: "{inproject}: Assets/KeyStore/game.keystore", alias: "eggo", custom: 1),
              to: project.appendingPathComponent("ProjectSettings/ProjectSettings.asset"))
    let s = try #require(Local.androidSigning(project: project, profile: nil))
    #expect(s.keystore.path.hasSuffix("/Assets/KeyStore/game.keystore"))
    #expect(s.alias == "eggo")
    #expect(s.custom)
}

/// Build Profiles override player settings as quoted "line" entries (format seen in a real project).
@Test func profileOverridesPlayerSettings() throws {
    let project = try unityProject()
    try write(playerSettingsAsset(keystore: "/Users/dev/release.keystore", alias: "release", custom: 1),
              to: project.appendingPathComponent("ProjectSettings/ProjectSettings.asset"))
    try write("""
    MonoBehaviour:
      m_Name: Android_DEV
        - line: '|   AndroidKeystoreName: ''{inproject}: Assets/KeyStore/dev.keystore'''
        - line: '|   AndroidKeyaliasName: dev'
        - line: '|   androidUseCustomKeystore: 0'
    """, to: project.appendingPathComponent("Assets/Settings/BuildProfiles/Android_DEV.asset"))
    let s = try #require(Local.androidSigning(project: project, profile: "Assets/Settings/BuildProfiles/Android_DEV.asset"))
    #expect(s.keystore.path.hasSuffix("/Assets/KeyStore/dev.keystore"))
    #expect(s.alias == "dev")
    #expect(!s.custom)
}

@Test func absoluteKeystorePathIsKept() throws {
    let project = try unityProject()
    try write(playerSettingsAsset(keystore: "/Users/dev/release.keystore", alias: "release", custom: 1),
              to: project.appendingPathComponent("ProjectSettings/ProjectSettings.asset"))
    #expect(Local.androidSigning(project: project, profile: nil)?.keystore.path == "/Users/dev/release.keystore")
}

/// The CLI rejects keystore flags without --execute-method, so signed builds go through our build script.
@Test func scriptBuildArguments() {
    #expect(BuildScript.arguments(project: "/p", target: .android, output: "/o/Game.apk", allowDirty: false)
            == ["build", "/p", "--output-path", "/o/Game.apk", "--target", "Android", "--execute-method", "UnityLauncherBuild.Build"])
    #expect(BuildScript.arguments(project: "/p", target: .android, output: "/o", allowDirty: true).last == "--allow-dirty-build")
}

@Test func scriptEnvironmentCarriesProfileAndPasswords() {
    let env = BuildScript.environment(profile: "Assets/P.asset", keystorePassword: "k", aliasPassword: "")
    #expect(env == ["UNITY_LAUNCHER_PROFILE": "Assets/P.asset", "UNITY_LAUNCHER_KEYSTORE_PASS": "k"])
    #expect(BuildScript.environment(profile: "Assets/P.asset", keystorePassword: "k", aliasPassword: "a")["UNITY_LAUNCHER_KEYALIAS_PASS"] == "a")
}

@Test func installsAndUpdatesBuildScript() throws {
    let project = try unityProject()
    #expect(BuildScript.status(project: project) == .missing)
    try BuildScript.install(project: project)
    #expect(BuildScript.status(project: project) == .current)
    let file = project.appendingPathComponent(BuildScript.relativePath)
    #expect(try String(contentsOf: file, encoding: .utf8).contains("public static void Build()"))
    try "// old version".write(to: file, atomically: true, encoding: .utf8)
    #expect(BuildScript.status(project: project) == .outdated)
}

@Test func streamPassesExtraEnvironment() async throws {
    let cli = try fakeCLI(#"echo "{\"type\":\"result\",\"success\":true,\"message\":\"$UL_TEST\"}""#)
    var last: Frame?
    for try await f in cli.stream(["x"], environment: ["UL_TEST": "secret-ok"]) { last = f }
    #expect(last?.text == "secret-ok")
}

@MainActor @Test func runTaskForwardsEnvironmentWithoutLoggingIt() async throws {
    let cli = try fakeCLI(#"echo "{\"type\":\"result\",\"success\":${UL_TEST:+true}${UL_TEST:-false}}""#)
    let state = AppState(cli: cli)
    let item = state.runTask("Build", ["build", "/p"], refreshAfter: false, environment: ["UL_TEST": "x"])
    await item.task?.value
    #expect(item.state == .succeeded)
    #expect(!item.log.joined().contains("x"))
}
