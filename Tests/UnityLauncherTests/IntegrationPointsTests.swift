import Foundation
import Testing
@testable import UnityLauncher

func unityProject() throws -> URL {
    let root = try tempDir()
    try write("m_EditorVersion: 6000.3.16f1\n", to: root.appendingPathComponent("ProjectSettings/ProjectVersion.txt"))
    return root
}

@Test func detectsUnityProjectFolders() throws {
    #expect(Local.isUnityProject(try unityProject()))
    #expect(!Local.isUnityProject(try tempDir()))
}

@Test func projectPathFromCommandLine() throws {
    let project = try unityProject().path
    #expect(Local.projectPath(fromArguments: ["bin", "-projectPath", "/any/path"]) == "/any/path")
    #expect(Local.projectPath(fromArguments: ["bin", "-projectpath", "/any/path"]) == "/any/path")
    #expect(Local.projectPath(fromArguments: ["bin", project]) == project)
    #expect(Local.projectPath(fromArguments: ["bin", try tempDir().path]) == nil)
    #expect(Local.projectPath(fromArguments: ["bin", "-NSDocumentRevisionsDebugMode", "YES"]) == nil)
    #expect(Local.projectPath(fromArguments: ["bin"]) == nil)
}

@MainActor @Test func recentProjectsAreExistingNewestFirstMaxTen() {
    let state = AppState(cli: nil)
    state.projects = (0..<12).map { row("P\($0)", modified: Double($0)) } + [row("Gone", modified: 99, exists: false)]
    let recent = state.recentProjects
    #expect(recent.count == 10)
    #expect(recent.first?.project.title == "P11")
    #expect(!recent.contains { $0.project.title == "Gone" })
}

@Test func runPrettyPrintsDataPayload() async throws {
    let cli = try fakeCLI(#"echo '{"success":true,"data":{"b":1,"a":"x"},"errors":[],"warnings":[]}'"#)
    let text = try await cli.runPretty(["doctor"])
    #expect(text.contains("\"a\" : \"x\""))
    #expect(text.contains("\"b\" : 1"))
}

@Test func adbPrefersUnityBundledSDK() throws {
    let root = try tempDir()
    let app = root.appendingPathComponent("6000.3.16f1/Unity.app")
    let adb = root.appendingPathComponent("6000.3.16f1/PlaybackEngines/AndroidPlayer/SDK/platform-tools/adb")
    try write("#!/bin/sh", to: adb)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
    #expect(Local.adbPath(editorLocations: [root.appendingPathComponent("none/Unity.app").path, app.path]) == adb.path)
    #expect(Local.adbPath(editorLocations: [], fallbacks: []) == nil)
}

@MainActor @Test func openPathRejectsNonProjectFolders() async throws {
    let marker = try tempDir().appendingPathComponent("called")
    let state = AppState(cli: try fakeCLI("touch '\(marker.path)'; echo '{\"success\":true,\"data\":null,\"errors\":[],\"warnings\":[]}'"))
    await state.openPath(try tempDir().path)
    #expect(state.errorMessage?.contains("not a Unity project") == true)
    #expect(!FileManager.default.fileExists(atPath: marker.path))

    state.errorMessage = nil
    await state.openPath(try unityProject().path)
    #expect(state.errorMessage == nil)
    #expect(FileManager.default.fileExists(atPath: marker.path))
}
