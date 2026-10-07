import Foundation
import Testing
@testable import UnityLauncher

/// Trimmed `xcrun devicectl list devices --json-output` (Xcode 27).
let devicectlJSON = #"""
{"info":{"outcome":"success"},"result":{"devices":[
 {"hardwareProperties":{"udid":"00008130-001E6CD10C89001C","platform":"iOS","reality":"physical","deviceType":"iPhone"},
  "deviceProperties":{"name":"Kai’s iPhone","developerModeStatus":"enabled"},
  "connectionProperties":{"pairingState":"paired","tunnelState":"connected","transportType":"wired"}},
 {"hardwareProperties":{"udid":"CB8B5088","platform":"iOS","reality":"simulated","deviceType":"iPhone"},
  "deviceProperties":{"name":"iPhone 18 Pro"},
  "connectionProperties":{"pairingState":"paired","tunnelState":"disconnected","transportType":"sameMachine"}},
 {"hardwareProperties":{"udid":"WATCH1","platform":"watchOS","reality":"physical","deviceType":"appleWatch"},
  "deviceProperties":{"name":"Watch"},
  "connectionProperties":{"pairingState":"paired","tunnelState":"connected"}}
]}}
"""#

@Test func picksPairedPhysicalIOSDevices() {
    let devices = IPhone.devices(fromDevicectlJSON: Data(devicectlJSON.utf8))
    #expect(devices == [IPhone.Device(udid: "00008130-001E6CD10C89001C", name: "Kai’s iPhone")])
    #expect(IPhone.devices(fromDevicectlJSON: Data("garbage".utf8)).isEmpty)
}

@Test func validatesTeamID() {
    #expect(IPhone.isValidTeamID("ABCDE12345"))
    #expect(!IPhone.isValidTeamID("abcde12345"))
    #expect(!IPhone.isValidTeamID("ABC123"))
    #expect(!IPhone.isValidTeamID(""))
}

@Test func xcodebuildUsesWorkspaceOrProject() {
    let dd = URL(fileURLWithPath: "/b/DerivedData")
    let ws = IPhone.xcodebuildArguments(project: URL(fileURLWithPath: "/b/Unity-iPhone.xcworkspace"), team: "ABCDE12345", derivedData: dd)
    #expect(Array(ws.prefix(4)) == ["-workspace", "/b/Unity-iPhone.xcworkspace", "-scheme", "Unity-iPhone"])
    #expect(ws.contains("DEVELOPMENT_TEAM=ABCDE12345"))
    #expect(ws.contains("-allowProvisioningUpdates"))
    #expect(ws.suffix(1) == ["build"])
    let proj = IPhone.xcodebuildArguments(project: URL(fileURLWithPath: "/b/Unity-iPhone.xcodeproj"), team: "ABCDE12345", derivedData: dd)
    #expect(proj.first == "-project")
}

@Test func extractsXcodebuildErrors() {
    let out = """
    note: Building targets in dependency order
    /b/Classes/Main.mm:12:5: error: use of undeclared identifier 'foo'
    /b/Classes/Main.mm:12:5: error: use of undeclared identifier 'foo'
    error: No Account for Team "ABCDE12345". Add a new account in Accounts settings.
    warning: something harmless
    ** BUILD FAILED **
    """
    #expect(IPhone.errors(fromXcodebuild: out) == ["/b/Classes/Main.mm:12:5: error: use of undeclared identifier 'foo'",
                                                    "error: No Account for Team \"ABCDE12345\". Add a new account in Accounts settings."])
}

@Test func findsBuiltAppAndBundleID() throws {
    let dd = try tempDir().appendingPathComponent("DerivedData")
    let app = dd.appendingPathComponent("Build/Products/Debug-iphoneos/Eggoo.app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.silvertiger.eggoo"], format: .xml, options: 0)
    try plist.write(to: app.appendingPathComponent("Info.plist"))
    #expect(IPhone.builtApp(in: dd)?.lastPathComponent == "Eggoo.app")
    #expect(IPhone.bundleID(of: app) == "com.silvertiger.eggoo")
    #expect(IPhone.builtApp(in: try tempDir()) == nil)
}

@Test func teamIDIsRememberedPerProject() {
    let path = "/tmp/\(UUID().uuidString)"
    #expect(ProjectPrefs.teamID(for: path) == "")
    ProjectPrefs.setTeamID("ABCDE12345", for: path)
    #expect(ProjectPrefs.teamID(for: path) == "ABCDE12345")
    ProjectPrefs.setTeamID("", for: path)
    #expect(ProjectPrefs.teamID(for: path) == "")
}

/// Shape of Xcode's IDEProvisioningTeamByIdentifier default: account id → [team dicts].
@Test func readsTeamsSignedIntoXcode() {
    let defaults: [String: Any] = [
        "acct-1": [["teamID": "4VGABCDE12", "teamName": "CLOUD SOFTWARE STUDIO L.L.C", "teamType": "Company"],
                   ["teamID": "2NSABCDE12", "teamName": "kai nguyen (Personal Team)", "teamType": "Personal Team"]],
        "acct-2": [["teamID": "4VGABCDE12", "teamName": "CLOUD SOFTWARE STUDIO L.L.C"]],
    ]
    #expect(IPhone.teams(fromXcodeDefaults: defaults) == [IPhone.Team(id: "4VGABCDE12", name: "CLOUD SOFTWARE STUDIO L.L.C"),
                                                          IPhone.Team(id: "2NSABCDE12", name: "kai nguyen (Personal Team)")])
    #expect(IPhone.teams(fromXcodeDefaults: [:]).isEmpty)
}
