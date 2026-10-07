import Foundation
import Testing
@testable import UnityLauncher

/// Trimmed `xcrun simctl list devices available -j` (Xcode 27).
let simctlJSON = #"""
{"devices":{
 "com.apple.CoreSimulator.SimRuntime.watchOS-27-0":[{"udid":"W1","state":"Shutdown","name":"Apple Watch","isAvailable":true}],
 "com.apple.CoreSimulator.SimRuntime.iOS-27-0":[
   {"udid":"CB8B5088","state":"Shutdown","name":"iPhone 18 Pro","isAvailable":true},
   {"udid":"A2C56344","state":"Booted","name":"iPhone Air","isAvailable":true},
   {"udid":"DEAD0000","state":"Shutdown","name":"Broken","isAvailable":false}],
 "com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"udid":"OLD00001","state":"Shutdown","name":"iPhone 16","isAvailable":true}]
}}
"""#

@Test func listsIOSSimulatorsBootedFirst() {
    let sims = IPhone.simulators(fromSimctlJSON: Data(simctlJSON.utf8))
    #expect(sims.map(\.name) == ["iPhone Air", "iPhone 18 Pro", "iPhone 16"])
    #expect(sims.first?.runtime == "iOS 27.0")
    #expect(sims.first?.booted == true)
    #expect(sims.last?.runtime == "iOS 26.2")
}

@Test func listsAndroidDevicesWithModels() {
    let out = """
    List of devices attached
    R58M12ABC              device usb:1-1 product:a52qnsxx model:SM_A525F device:a52q transport_id:1
    emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:2
    ZY22                   unauthorized usb:1-2 transport_id:3

    """
    #expect(Android.deviceList(fromADBOutput: out) == [Android.Device(serial: "R58M12ABC", model: "SM A525F"),
                                                       Android.Device(serial: "emulator-5554", model: "sdk gphone64 arm64")])
}

@Test func simulatorBuildNeedsNoSigning() {
    let args = IPhone.xcodebuildArguments(project: URL(fileURLWithPath: "/b/Unity-iPhone.xcworkspace"), team: nil,
                                          derivedData: URL(fileURLWithPath: "/b/dd"), configuration: "ReleaseForRunning", simulator: "CB8B5088")
    // The chosen simulator, active architecture only: Xcode 27 simulators are arm64.
    #expect(args.firstIndex(of: "-destination").map { args[$0 + 1] } == "platform=iOS Simulator,id=CB8B5088")
    #expect(args.contains("ONLY_ACTIVE_ARCH=YES"))
    #expect(args.contains("CODE_SIGNING_ALLOWED=NO"))
    #expect(!args.contains { $0.hasPrefix("DEVELOPMENT_TEAM") })
    #expect(!args.contains("-allowProvisioningUpdates"))
}

@Test func simulatorProductsFolder() throws {
    let dd = try tempDir()
    let app = dd.appendingPathComponent("Build/Products/ReleaseForRunning-iphonesimulator/Eggoo.app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    #expect(IPhone.builtApp(in: dd, configuration: "ReleaseForRunning", simulator: true)?.lastPathComponent == "Eggoo.app")
    #expect(IPhone.builtApp(in: dd, configuration: "ReleaseForRunning") == nil)
}

@Test func scriptCanBuildForTheSimulatorSDK() {
    #expect(BuildScript.environment(profile: "Assets/iOS.asset", iosSimulator: true)["UNITY_LAUNCHER_IOS_SDK"] == "simulator")
    #expect(BuildScript.environment(profile: "Assets/iOS.asset")["UNITY_LAUNCHER_IOS_SDK"] == nil)
    // Restores the profile's SDK afterwards so the project isn't left switched.
    #expect(BuildScript.source.contains("iOSSdkVersion.SimulatorSDK"))
    // Unity defaults the simulator architecture to x86_64, which Apple-silicon simulators can't run.
    #expect(BuildScript.source.contains("AppleMobileArchitectureSimulator.ARM64"))
    #expect(BuildScript.source.contains("finally"))
}

@Test func remembersLastDevicePerProjectAndKind() {
    let path = "/tmp/\(UUID().uuidString)"
    #expect(ProjectPrefs.lastDevice(for: path, kind: "ios") == nil)
    ProjectPrefs.setLastDevice("A2C56344", for: path, kind: "simulator")
    #expect(ProjectPrefs.lastDevice(for: path, kind: "simulator") == "A2C56344")
    #expect(ProjectPrefs.lastDevice(for: path, kind: "ios") == nil)
}

/// Real output (order kept) from linking Capy_2D for an arm64 simulator: the line naming the
/// device-only library comes last, so it must be moved to the front.
@Test func namesDeviceOnlyLibraryFirst() {
    let out = """
    Unity-iPhone.xcodeproj: UnityFramework: clang++: error: linker command failed with exit code 1 (use -v to see invocation)
    error: the following command failed with exit code 0 but produced no further output
    ld: building for 'iOS-simulator', but linking in object file (Libraries/Plugins/iOS/Firebase/libFirebaseCppAnalytics.a[arm64][2](analytics_common.cc.o)) built for 'iOS'
    """
    let errors = IPhone.errors(fromXcodebuild: out)
    #expect(errors.first?.contains("libFirebaseCppAnalytics.a") == true)
    #expect(errors.count == 3)
}

/// Shared by the Build sheet's "Simulator build" and the Simulators section of a device build's menu.
@Test func simulatorBuildCommand() {
    let cmd = BuildScript.simulatorBuild(project: "/p", profile: "Assets/Settings/BuildProfiles/iOS_DEV.asset", allowDirty: false)
    #expect(cmd.output == "/p/Builds/iOS-Simulator")
    #expect(cmd.arguments == ["build", "/p", "--output-path", "/p/Builds/iOS-Simulator", "--target", "iOS",
                              "--execute-method", "UnityLauncherBuild.Build"])
    #expect(cmd.environment == ["UNITY_LAUNCHER_PROFILE": "Assets/Settings/BuildProfiles/iOS_DEV.asset",
                                "UNITY_LAUNCHER_IOS_SDK": "simulator"])
}
