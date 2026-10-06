import Foundation
import Testing
@testable import UnityLauncher

/// Runs against the real Unity CLI. Opt in with `UNITY_INTEGRATION=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["UNITY_INTEGRATION"] == "1"))
struct RealCLITests {
    let cli = UnityCLI.locate(override: nil).map(UnityCLI.init)

    @Test func listsProjectsAndEditors() async throws {
        let cli = try #require(cli)
        let projects = try await cli.run(["projects", "list"], as: [Project].self)
        let editors = try await cli.run(["editors", "--installed"], as: [EditorInstall].self)
        #expect(!editors.isEmpty)
        if let first = projects.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            let size = try await cli.run(["projects", "size", first.path], as: ProjectSize.self)
            #expect(size.total > 0)
        }
    }

    @MainActor @Test func verifyStreamsToSuccessfulTask() async throws {
        let cli = try #require(cli)
        let projects = try await cli.run(["projects", "list"], as: [Project].self)
        let path = try #require(projects.first { FileManager.default.fileExists(atPath: $0.path) }?.path)
        let state = AppState(cli: cli)
        let item = state.runTask("Verify", ["projects", "verify", path], refreshAfter: false)
        await item.task?.value
        // A real project may legitimately have findings; either way the task must finish and explain itself.
        #expect(item.state != .running)
        if item.state != .succeeded { #expect(item.log.contains { $0.hasPrefix("error ") || $0.hasPrefix("warning ") }) }
    }

    /// Needs a Unity 6 Editor open with the Pipeline package; passes trivially otherwise.
    @MainActor @Test func drivesRunningEditorReadOnly() async throws {
        let cli: UnityCLI = try #require(cli)
        let model = LiveModel(cli: cli)
        await model.refreshInstances()
        guard model.selected != nil else { return }
        await model.poll()
        #expect(model.status?.playMode != nil)
        model.evalCode = "return Application.unityVersion;"
        await model.eval()
        #expect(UnityVersion(model.evalOutput) != nil)
        model.commandLine = "editor_status"
        await model.runCommandLine()
        #expect(model.commandOutput.contains("playMode"))
        #expect(model.error == nil)
    }

    @Test func listsTemplatesAndReleases() async throws {
        let cli = try #require(cli)
        let editors = try await cli.run(["editors", "--installed"], as: [EditorInstall].self)
        let version = try #require(editors.map(\.version).sorted(by: UnityVersion.newerFirst).first)
        let templates = try await cli.run(["templates", "list", "--editor", version, "--type", "core"], as: [Template].self)
        #expect(!templates.isEmpty)
        let releases = try await cli.run(["releases", "--limit", "5"], as: [Release].self)
        #expect(releases.count == 5)
    }
}
