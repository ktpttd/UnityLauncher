import Foundation
import Testing
@testable import UnityLauncher

let provenanceJSON = """
{
 "schemaVersion": 1,
 "outcome": "success",
 "exitCode": 0,
 "startedAt": "2026-10-06T18:08:04.493Z",
 "endedAt": "2026-10-06T18:09:43.882Z",
 "editor": { "version": "6000.3.16f1", "changeset": "a56f230f6470", "architecture": "arm64" },
 "build": {
  "target": "iOS_INTERNAL",
  "profile": "Assets/Settings/BuildProfiles/iOS_INTERNAL.asset",
  "outputPath": "Builds/iOS",
  "logFile": "Logs/build-iOS_INTERNAL-1791310084383.log"
 },
 "source": { "vcs": "git", "revision": "7ae599a1f3e7e56e3d148efaa084b6ee9d31ea9a", "dirty": true }
}
"""

@Test func formatsDurations() {
    #expect(formatDuration(5) == "5s")
    #expect(formatDuration(99.4) == "1m 39s")
    #expect(formatDuration(3725) == "1h 2m 5s")
}

@Test func decodesBuildProvenance() throws {
    let p = try BuildProvenance.decode(Data(provenanceJSON.utf8))
    #expect(formatDuration(p.duration) == "1m 39s")
    #expect(p.build.outputPath == "Builds/iOS")
    #expect(p.source?.dirty == true)
    #expect(p.editor?.version == "6000.3.16f1")
}

@Test func findsProvenanceForALogFile() throws {
    let project = try unityProject()
    try write(provenanceJSON, to: project.appendingPathComponent("Builds/iOS/unity-build.provenance.json"))
    let log = project.appendingPathComponent("Logs/build-iOS_INTERNAL-1791310084383.log")
    #expect(BuildProvenance.find(project: project, logFile: log)?.build.target == "iOS_INTERNAL")
    #expect(BuildProvenance.find(project: project, logFile: project.appendingPathComponent("Logs/other.log")) == nil)
}

@Test func diskSizeSumsFilesInFolderOrSingleFile() throws {
    let dir = try tempDir()
    try write(String(repeating: "a", count: 1000), to: dir.appendingPathComponent("a.txt"))
    try write(String(repeating: "b", count: 500), to: dir.appendingPathComponent("sub/b.txt"))
    #expect(Local.diskSize(dir) == 1500)
    #expect(Local.diskSize(dir.appendingPathComponent("a.txt")) == 1000)
    #expect(Local.diskSize(dir.appendingPathComponent("missing")) == nil)
}

@MainActor @Test func finishedTasksRecordElapsedTime() async throws {
    let state = AppState(cli: try fakeCLI(#"echo '{"type":"result","success":true,"errors":[]}'"#))
    let item = state.runTask("Verify", ["projects", "verify", "/p"], refreshAfter: false)
    await item.task?.value
    #expect(item.finishedAt != nil)
    #expect(item.summary == nil)
}

@MainActor @Test func buildTaskSummarizesOutputSize() async throws {
    let out = try tempDir().appendingPathComponent("Game.app")
    try write(String(repeating: "x", count: 2048), to: out.appendingPathComponent("Contents/MacOS/Game"))
    let state = AppState(cli: try fakeCLI(#"echo '{"type":"result","success":true,"errors":[]}'"#))
    let item = state.runTask("Build", ["build", "/p", "--output-path", out.path, "--target", "StandaloneOSX"], refreshAfter: false)
    await item.task?.value
    let summary = try #require(item.summary)
    #expect(summary.contains("Game.app"))
    #expect(summary.contains("KB"))
}
