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

@Test func buildArgumentsCarryKeystoreFlags() {
    let signing = AndroidSigningArgs(keystoreBase64: "QUJD", password: "p1", alias: "eggo", aliasPassword: "")
    let args = BuildTarget.arguments(project: "/p", target: .android, profile: "Assets/A.asset", output: "/o", allowDirty: false, signing: signing)
    #expect(args == ["build", "/p", "--output-path", "/o", "--profile", "Assets/A.asset",
                     "--android-keystore-base64", "QUJD", "--android-keystore-password", "p1", "--android-key-alias", "eggo"])
    let withAlias = AndroidSigningArgs(keystoreBase64: "QUJD", password: "p1", alias: "eggo", aliasPassword: "p2")
    #expect(BuildTarget.arguments(project: "/p", target: .android, profile: nil, output: "/o", allowDirty: false, signing: withAlias).suffix(2)
            == ["--android-key-alias-password", "p2"])
}
