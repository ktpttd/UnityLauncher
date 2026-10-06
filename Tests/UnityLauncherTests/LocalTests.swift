import Foundation
import Testing
@testable import UnityLauncher

func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

@Test func branchFromHeadRef() throws {
    let root = try tempDir()
    try write("ref: refs/heads/feature/login\n", to: root.appendingPathComponent(".git/HEAD"))
    #expect(Local.gitBranch(at: root) == "feature/login")
}

@Test func branchDetachedShowsShortHash() throws {
    let root = try tempDir()
    try write("a56f230f6470b1c2d3e4f5a6b7c8d9e0f1a2b3c4\n", to: root.appendingPathComponent(".git/HEAD"))
    #expect(Local.gitBranch(at: root) == "a56f230")
}

@Test func branchFoundInParentFolder() throws {
    let root = try tempDir()
    try write("ref: refs/heads/main\n", to: root.appendingPathComponent(".git/HEAD"))
    let project = root.appendingPathComponent("Games/MyGame")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    #expect(Local.gitBranch(at: project) == "main")
}

@Test func branchFollowsWorktreeGitFile() throws {
    let root = try tempDir()
    let gitdir = root.appendingPathComponent("repo/.git/worktrees/wt")
    try write("ref: refs/heads/wt-branch\n", to: gitdir.appendingPathComponent("HEAD"))
    let wt = root.appendingPathComponent("wt")
    try write("gitdir: \(gitdir.path)\n", to: wt.appendingPathComponent(".git"))
    #expect(Local.gitBranch(at: wt) == "wt-branch")
}

@Test func noBranchWithoutGit() throws {
    #expect(Local.gitBranch(at: try tempDir()) == nil)
}

@Test func parsesUnityProcesses() {
    let ps = """
      123 /Applications/Unity/Hub/Editor/6000.3.16f1/Unity.app/Contents/MacOS/Unity -projectpath /Users/dev/My Game -useHub -hubIPC
      456 /usr/bin/ssh-agent -l
      789 /Applications/Unity/Hub/Editor/2022.3.62f3/Unity.app/Contents/MacOS/Unity -projectPath /Users/dev/pa-spikes
      790 /Applications/Unity/Hub/Editor/2022.3.62f3/Unity.app/Contents/MacOS/Unity
    """
    let result = Local.parseUnityProcesses(ps)
    #expect(result.map(\.pid) == [123, 789])
    #expect(result.map(\.projectPath) == ["/Users/dev/My Game", "/Users/dev/pa-spikes"])
}

@Test func readsPlayerSettings() throws {
    let root = try tempDir()
    try write("""
    PlayerSettings:
      m_ObjectHideFlags: 0
      companyName: Silver Tiger
      productName: Eggoo : Roguelike
      defaultScreenWidth: 1024
    """, to: root.appendingPathComponent("ProjectSettings/ProjectSettings.asset"))
    let s = try #require(Local.playerSettings(at: root))
    #expect(s.company == "Silver Tiger")
    #expect(s.product == "Eggoo : Roguelike")
    #expect(Local.playerLogURL(company: s.company, product: s.product).path.hasSuffix("Library/Logs/Silver Tiger/Eggoo : Roguelike/Player.log"))
}

@Test func projectArgsRoundTrip() {
    let path = "/tmp/\(UUID().uuidString)"
    #expect(ProjectPrefs.args(for: path) == "")
    ProjectPrefs.setArgs("-logFile out.log", for: path)
    #expect(ProjectPrefs.args(for: path) == "-logFile out.log")
    ProjectPrefs.setArgs("", for: path)
    #expect(ProjectPrefs.args(for: path) == "")
}
