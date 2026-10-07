import Foundation
import Testing
@testable import UnityLauncher

/// Shape of ProjectSettings.asset (plain YAML), including the applicationIdentifier map that also has an iPhone key.
let playerSettingsText = """
PlayerSettings:
  visionOSBundleVersion: 1.0
  tvOSBundleVersion: 1.0
  bundleVersion: 1.2
  applicationIdentifier:
    Standalone: com.Unity-Technologies.com.unity.template.urp-blank
    iPhone: com.silvertiger.eggoo
  buildNumber:
    Standalone: 0
    VisionOS: 0
    iPhone: 2
    tvOS: 0
  AndroidBundleVersionCode: 32
"""

/// Shape of a Build Profile's player-settings override (seen in a real project).
let profileText = """
  m_PlayerSettingsYaml:
    m_Settings:
    - line: '|   visionOSBundleVersion: 1.0'
    - line: '|   bundleVersion: 2.5.0'
    - line: '|   applicationIdentifier:'
    - line: '|     iPhone: com.silvertiger.eggoo'
    - line: '|   buildNumber:'
    - line: '|     Standalone: 0'
    - line: '|     iPhone: 62'
    - line: '|     tvOS: 0'
    - line: '|   overrideDefaultApplicationIdentifier: 1'
    - line: '|   AndroidBundleVersionCode: 1567'
"""

@Test func readsVersionsFromPlayerSettings() {
    #expect(BuildVersion.read(playerSettingsText) == BuildVersion(version: "1.2", androidCode: "32", iosBuild: "2"))
}

@Test func readsVersionsFromProfileOverride() {
    #expect(BuildVersion.read(profileText) == BuildVersion(version: "2.5.0", androidCode: "1567", iosBuild: "62"))
}

@Test func writesOnlyTheThreeValues() {
    let updated = BuildVersion(version: "2.6.0", androidCode: "1568", iosBuild: "63").write(into: profileText)
    #expect(BuildVersion.read(updated) == BuildVersion(version: "2.6.0", androidCode: "1568", iosBuild: "63"))
    let before = profileText.split(separator: "\n"), after = updated.split(separator: "\n")
    #expect(before.count == after.count)
    #expect(zip(before, after).filter { $0 != $1 }.count == 3)
    #expect(updated.contains("visionOSBundleVersion: 1.0"))
    #expect(updated.contains("iPhone: com.silvertiger.eggoo"))
}

@Test func writesPlayerSettingsToo() {
    let updated = BuildVersion(version: "1.3", androidCode: "33", iosBuild: "3").write(into: playerSettingsText)
    #expect(BuildVersion.read(updated) == BuildVersion(version: "1.3", androidCode: "33", iosBuild: "3"))
    #expect(updated.contains("    iPhone: com.silvertiger.eggoo"))
}

@Test func validatesInput() {
    #expect(BuildVersion(version: "2.5.0", androidCode: "1567", iosBuild: "62.1").problem == nil)
    #expect(BuildVersion(version: "2.5 beta", androidCode: "1", iosBuild: "1").problem != nil)
    #expect(BuildVersion(version: "2.5.0", androidCode: "0", iosBuild: "1").problem != nil)
    #expect(BuildVersion(version: "2.5.0", androidCode: "12a", iosBuild: "1").problem != nil)
    #expect(BuildVersion(version: "2.5.0", androidCode: "1", iosBuild: "1a").problem != nil)
}

@Test func versionFileIsTheProfileOrPlayerSettings() {
    let p = URL(fileURLWithPath: "/proj")
    #expect(BuildVersion.file(project: p, profile: "Assets/Settings/BuildProfiles/iOS_DEV.asset").path == "/proj/Assets/Settings/BuildProfiles/iOS_DEV.asset")
    #expect(BuildVersion.file(project: p, profile: nil).path == "/proj/ProjectSettings/ProjectSettings.asset")
}

@Test func bumpIncrementsLastNumber() {
    #expect(BuildVersion.bump("62") == "63")
    #expect(BuildVersion.bump("62.1") == "62.2")
    #expect(BuildVersion.bump("1567") == "1568")
    #expect(BuildVersion.bump("") == "")
    #expect(BuildVersion.bump("abc") == "abc")
}
