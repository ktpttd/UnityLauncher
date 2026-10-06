import Foundation
import Testing
@testable import UnityLauncher

@Test func decodesModulesWithStatus() throws {
    let modules = try JSONDecoder().decode([ModuleInfo].self, from: Data(#"""
    [{"id":"ios","aliases":"","name":"iOS Build Support","category":"Platforms","status":"Installed","download":"1 GB","installed":"2 GB"},
     {"id":"webgl","aliases":"","name":"Web Build Support","category":"Platforms","status":"Available","download":"1 GB","installed":"2 GB"}]
    """#.utf8))
    #expect(modules.map(\.isInstalled) == [true, false])
    #expect(modules[1].name == "Web Build Support")
}

@Test func releaseNotesURLPerStream() {
    #expect(UnityVersion.releaseNotesURL("6000.3.16f1")?.absoluteString == "https://unity.com/releases/editor/whats-new/6000.3.16")
    #expect(UnityVersion.releaseNotesURL("6000.7.0b3")?.absoluteString == "https://unity.com/releases/editor/beta/6000.7.0b3")
    #expect(UnityVersion.releaseNotesURL("7000.0.0a7")?.absoluteString == "https://unity.com/releases/editor/alpha/7000.0.0a7")
    #expect(UnityVersion.releaseNotesURL("junk") == nil)
}

@MainActor @Test func releasesFilterBySearch() throws {
    let state = AppState(cli: nil)
    state.releases = try #require(try JSONDecoder().decode(Envelope<[Release]>.self, from: fixture("releases")).data)
    state.releaseSearch = "6000"
    #expect(state.filteredReleases.map(\.version) == ["6000.3.16f1"])
    state.releaseSearch = ""
    #expect(state.filteredReleases.count == 2)
}

@Test func releaseArgumentsPerStream() {
    #expect(AppState.releaseArguments(stream: .all) == ["releases", "--limit", "200"])
    #expect(AppState.releaseArguments(stream: .lts) == ["releases", "--limit", "200", "--stream", "lts"])
}

@Test func moduleAddArguments() {
    #expect(AppState.moduleAddArguments(version: "6000.3.16f1", modules: ["webgl", "ios"])
            == ["editors", "module", "add", "6000.3.16f1", "--module", "webgl", "--module", "ios", "--accept-eula"])
}
