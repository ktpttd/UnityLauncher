import Foundation
import Testing
@testable import UnityLauncher

@Test func findsSigningFailureWithItsExplanation() {
    let log = """
    System.NullReferenceException: Object reference not set to an instance of an object.
      at Foo.Bar () [0x00000] in <abc>:0
    DisplayProgressbar: Checking prerequisites
    UnityException: Can not sign the application
    Unable to sign the application; please provide passwords!
    UnityEditor.BuildPipeline:BuildPlayerInternalNoCheck(String[], String, String, BuildTargetGroup)
    Build Finished, Result: Failure.
    """
    // Harmless NullReferenceExceptions show up in successful builds too, so they're not reported.
    #expect(BuildErrors.find(in: log) == ["UnityException: Can not sign the application",
                                           "Unable to sign the application; please provide passwords!"])
}

@Test func findsCompileErrorsOnce() {
    let log = """
    Assets/Scripts/Player.cs(12,5): error CS0103: The name 'speed' does not exist in the current context
    Assets/Scripts/Player.cs(12,5): error CS0103: The name 'speed' does not exist in the current context
    Assets/Editor/UnityLauncherBuild.cs(44,16): warning CS8603: Possible null reference return.
    Scripts have compiler errors.
    """
    #expect(BuildErrors.find(in: log) == ["Assets/Scripts/Player.cs(12,5): error CS0103: The name 'speed' does not exist in the current context",
                                           "Scripts have compiler errors."])
}

@Test func findsGradleFailureReason() {
    let log = """
    FAILURE: Build failed with an exception.
    * What went wrong:
    Execution failed for task ':launcher:packageRelease'.
    * Try:
    """
    #expect(BuildErrors.find(in: log) == ["Execution failed for task ':launcher:packageRelease'."])
}

@Test func findsLauncherScriptAndPlayerErrors() {
    let log = """
    Exception: Unity Launcher: Build Profile not found: Assets/Missing.asset
    Error building Player: 2 errors
    BuildFailedException: Incremental Player build failed!
    """
    #expect(BuildErrors.find(in: log) == ["Exception: Unity Launcher: Build Profile not found: Assets/Missing.asset",
                                           "Error building Player: 2 errors",
                                           "BuildFailedException: Incremental Player build failed!"])
}

@Test func capsAtFourLinesAndIgnoresCleanLogs() {
    let many = (1...10).map { "Assets/A\($0).cs(1,1): error CS1002: ; expected" }.joined(separator: "\n")
    #expect(BuildErrors.find(in: many).count == 4)
    #expect(BuildErrors.find(in: "Build Finished, Result: Success.").isEmpty)
}

@Test func newestBuildLogIsPicked() throws {
    let project = try unityProject()
    let old = project.appendingPathComponent("Logs/build-iOS-1.log"), new = project.appendingPathComponent("Logs/build-Android-2.log")
    try write("old", to: old)
    try write("new", to: new)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: old.path)
    #expect(BuildErrors.latestLog(project: project)?.lastPathComponent == "build-Android-2.log")
}

@MainActor @Test func failedBuildTaskShowsErrorsFromItsLog() async throws {
    let project = try unityProject()
    try write("UnityException: Can not sign the application\nUnable to sign the application; please provide passwords!\n",
              to: project.appendingPathComponent("Logs/build-Android_INTERNAL-1.log"))
    let state = AppState(cli: try fakeCLI(#"echo '{"type":"result","success":false,"errors":[{"code":"BUILD_FAILED","message":"Build failed"}]}'; exit 6"#))
    let item = state.runTask("Build", ["build", project.path, "--output-path", "/o", "--target", "Android"], refreshAfter: false)
    await item.task?.value
    #expect(item.state == .failed("Build failed"))
    #expect(item.failureDetails == ["UnityException: Can not sign the application", "Unable to sign the application; please provide passwords!"])
}
