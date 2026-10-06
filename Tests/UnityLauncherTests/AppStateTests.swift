import Foundation
import Testing
@testable import UnityLauncher

func row(_ title: String, path: String? = nil, modified: Double, pinned: Bool = false, exists: Bool = true) -> ProjectRow {
    let json = """
    {"title":"\(title)","path":"\(path ?? "/Work/\(title)")","version":"6000.3.16f1","lastModified":\(modified),"isFavorite":\(pinned)}
    """
    let project = try! JSONDecoder().decode(Project.self, from: Data(json.utf8))
    return ProjectRow(project: project, exists: exists, branch: nil, pid: nil)
}

@MainActor @Test func sortsPinnedFirstThenNewest() {
    let state = AppState(cli: nil)
    state.projects = [row("Old", modified: 1), row("New", modified: 3), row("Pinned", modified: 2, pinned: true)]
    #expect(state.filteredProjects.map(\.project.title) == ["Pinned", "New", "Old"])
}

@MainActor @Test func searchMatchesTitleOrPathCaseInsensitive() {
    let state = AppState(cli: nil)
    state.projects = [row("Capy", path: "/Clients/Acme/Capy", modified: 1), row("Other", modified: 2)]
    state.search = "acme"
    #expect(state.filteredProjects.map(\.project.title) == ["Capy"])
    state.search = "OTH"
    #expect(state.filteredProjects.map(\.project.title) == ["Other"])
}

@MainActor @Test func hidesMissingProjectsWhenDisabled() {
    let state = AppState(cli: nil)
    state.projects = [row("Here", modified: 1), row("Gone", modified: 2, exists: false)]
    state.showMissing = false
    #expect(state.filteredProjects.map(\.project.title) == ["Here"])
    state.showMissing = true
    #expect(state.filteredProjects.count == 2)
}

@MainActor @Test func openArgumentsIncludeVersionAndCustomArgs() {
    let path = "/Work/\(UUID().uuidString)"
    ProjectPrefs.setArgs("-logFile out.log", for: path)
    defer { ProjectPrefs.setArgs("", for: path) }
    #expect(AppState.openArguments(path: path, version: nil) == ["open", path, "--args", "-logFile out.log"])
    ProjectPrefs.setArgs("", for: path)
    #expect(AppState.openArguments(path: path, version: "2022.3.62f3") == ["open", path, "--editor-version", "2022.3.62f3"])
}

@Test func matchesRunningProcessIgnoringTrailingSlash() {
    let rows = AppState.rows(for: [row("A", path: "/Work/A", modified: 1).project],
                             running: [UnityProcess(pid: 42, projectPath: "/Work/A/")])
    #expect(rows.first?.pid == 42)
}
