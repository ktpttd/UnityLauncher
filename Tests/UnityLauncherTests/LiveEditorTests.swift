import Foundation
import Testing
@testable import UnityLauncher

@Test func splitsCommandLineWithQuotes() {
    #expect(splitArgs(#"create_gameobject --name "My Obj" --x 1"#) == ["create_gameobject", "--name", "My Obj", "--x", "1"])
    #expect(splitArgs("save_all") == ["save_all"])
    #expect(splitArgs("  a   'b c'  ") == ["a", "b c"])
    #expect(splitArgs("") == [])
}

@Test func decodesLiveStatus() throws {
    let status = try JSONDecoder().decode(LiveStatus.self, from: Data(#"""
    {"count":1,"instances":[{"port":7800,"project":"/Users/dev/Capy","version":"6000.3.16f1","pid":20975,"state":"ready"}]}
    """#.utf8))
    #expect(status.instances.first?.project == "/Users/dev/Capy")
    #expect(status.instances.first?.isReady == true)
}

@Test func decodesConsolePage() throws {
    let page = try JSONDecoder().decode(ConsolePage.self, from: Data(#"""
    {"entries":[{"seq":173,"timestampUtc":"2026-10-06T17:03:00.79241Z","level":"warn","logType":"Warning","message":"Missing asset","stackTrace":""}],
     "cursor":173,"session":"abc","returned":1,"counts":{"error":0,"warn":173,"log":1}}
    """#.utf8))
    #expect(page.entries.first?.level == "warn")
    #expect(page.entries.first?.id == 173)
    #expect(page.counts?.warn == 173)
}

@Test func decodesEditorStatus() throws {
    let s = try JSONDecoder().decode(EditorStatus.self, from: Data(#"""
    {"status":"ready","compiling":false,"domainReloadInProgress":false,"playMode":"stopped","unityVersion":"6000.3.16f1"}
    """#.utf8))
    #expect(s.playMode == "stopped")
    #expect(!s.compiling)
}

@Test func evalResultDisplaysValueOrOutput() throws {
    let r = try JSONDecoder().decode(EvalResult.self, from: Data(#"{"output":null,"diagnostics":[],"success":true,"result":"6000.3.16f1"}"#.utf8))
    #expect(r.display == "6000.3.16f1")
    let printed = try JSONDecoder().decode(EvalResult.self, from: Data(#"{"output":"hello\n","diagnostics":[],"success":true,"result":null}"#.utf8))
    #expect(printed.display == "hello")
    let number = try JSONDecoder().decode(EvalResult.self, from: Data(#"{"output":null,"success":true,"result":42}"#.utf8))
    #expect(number.display == "42")
}

@Test func liveCommandArgumentsTargetProject() {
    #expect(AppState.liveArgs("editor_play", project: "/p") == ["command", "editor_play", "--project-path", "/p"])
    #expect(AppState.liveArgs("eval", project: "/p", ["--code", "return 1;"]) == ["command", "eval", "--project-path", "/p", "--code", "return 1;"])
}

@Test func runPrettyCanPickAField() async throws {
    let cli = try fakeCLI(#"echo '{"success":true,"data":{"command":"x","result":{"ok":true},"target":{"port":1}},"errors":[],"warnings":[]}'"#)
    let text = try await cli.runPretty(["command", "x"], field: "result")
    #expect(text.contains("\"ok\" : true"))
    #expect(!text.contains("port"))
}

@Test func detectsPipelinePackage() throws {
    let project = try unityProject()
    try write(#"{"dependencies":{"com.unity.ugui":"2.0.0"}}"#, to: project.appendingPathComponent("Packages/manifest.json"))
    #expect(!Local.hasPipeline(project))
    try write(#"{"dependencies":{"com.unity.pipeline":"0.8.0-exp.1"}}"#, to: project.appendingPathComponent("Packages/manifest.json"))
    #expect(Local.hasPipeline(project))
}

@MainActor @Test func noRunningEditorsIsEmptyNotAnError() async throws {
    let model = LiveModel(cli: try fakeCLI(#"echo '{"success":false,"data":null,"errors":[{"code":"STATUS_NO_INSTANCES","message":"No editors"}],"warnings":[]}'; exit 6"#))
    await model.refreshInstances()
    #expect(model.instances.isEmpty)
    #expect(model.error == nil)
}

@MainActor @Test func selectsFirstInstanceAutomatically() async throws {
    let model = LiveModel(cli: try fakeCLI(#"echo '{"success":true,"data":{"count":1,"instances":[{"port":7800,"project":"/p","version":"6000.3.16f1","pid":1,"state":"ready"}]},"errors":[],"warnings":[]}'"#))
    await model.refreshInstances()
    #expect(model.selected == "/p")
}
