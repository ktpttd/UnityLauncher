import AppKit
import Observation

struct ProjectRow: Identifiable, Hashable, Sendable {
    var id: String { project.path }
    let project: Project
    let exists: Bool
    let branch: String?
    let pid: Int32?
}

@MainActor @Observable
final class AppState {
    var projects: [ProjectRow] = []
    var editors: [EditorInstall] = []
    var releases: [Release] = []
    var search = ""
    var isLoading = false
    var errorMessage: String?
    /// Project whose required editor isn't installed — drives the "missing editor" alert.
    var missingEditorFor: ProjectRow?
    var info: InfoMessage?
    /// Long monospaced report (Unity doctor) shown in a sheet.
    var report: InfoMessage?
    var tasks: [TaskItem] = []
    var showTasks = false
    var releaseSearch = ""
    var releaseStream = ReleaseStream.all
    var releasesLoading = false
    private(set) var cli: UnityCLI?

    var showMissing: Bool {
        didSet { UserDefaults.standard.set(showMissing, forKey: "showMissing") }
    }

    init(cli: UnityCLI? = UnityCLI.locate(override: UserDefaults.standard.string(forKey: "cliPath")).map(UnityCLI.init)) {
        self.cli = cli
        self.showMissing = UserDefaults.standard.object(forKey: "showMissing") as? Bool ?? true
    }

    func relocateCLI() {
        cli = UnityCLI.locate(override: UserDefaults.standard.string(forKey: "cliPath")).map(UnityCLI.init)
    }

    var installedVersions: Set<String> { Set(editors.map(\.version)) }

    var filteredProjects: [ProjectRow] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return projects
            .filter { showMissing || $0.exists }
            .filter { q.isEmpty || $0.project.title.localizedCaseInsensitiveContains(q) || $0.project.path.localizedCaseInsensitiveContains(q) }
            .sorted {
                let (a, b) = ($0.project, $1.project)
                if (a.isFavorite ?? false) != (b.isFavorite ?? false) { return a.isFavorite ?? false }
                return (a.lastModified ?? 0) > (b.lastModified ?? 0)
            }
    }

    /// Menu bar list: ten most recently modified projects that still exist.
    var recentProjects: [ProjectRow] {
        Array(projects.filter(\.exists).sorted { ($0.project.lastModified ?? 0) > ($1.project.lastModified ?? 0) }.prefix(10))
    }

    // MARK: Loading

    func refresh() async {
        guard let cli else { return }
        isLoading = true
        defer { isLoading = false }
        await perform {
            async let p = cli.run(["projects", "list"], as: [Project].self)
            async let e = cli.run(["editors", "--installed"], as: [EditorInstall].self)
            let (projects, editors) = try await (p, e)
            self.editors = editors.sorted { UnityVersion.newerFirst($0.version, $1.version) }
            self.projects = await Task.detached { Self.rows(for: projects, running: Local.runningUnity()) }.value
        }
    }

    nonisolated static func rows(for projects: [Project], running: [UnityProcess]) -> [ProjectRow] {
        func norm(_ p: String) -> String { URL(fileURLWithPath: p).standardizedFileURL.path.lowercased() }
        // Each process belongs to the longest known project path its args start with, so
        // "/Work/MyGame - Backup -useHub" never matches "/Work/MyGame".
        var pids: [String: Int32] = [:]
        for proc in running {
            let tail = proc.argsTail.lowercased()
            let owner = projects.map(\.path)
                .filter { path in [norm(path), norm(path) + "/"].contains { tail == $0 || tail.hasPrefix($0 + " ") } }
                .max { norm($0).count < norm($1).count }
            if let owner { pids[owner] = proc.pid }
        }
        return projects.map { p in
            ProjectRow(project: p,
                       exists: FileManager.default.fileExists(atPath: p.path),
                       branch: Local.gitBranch(at: URL(fileURLWithPath: p.path)),
                       pid: pids[p.path])
        }
    }

    /// Runs a CLI action, surfacing any error as an alert.
    func perform(_ op: () async throws -> Void) async {
        do { try await op() } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Project actions

    nonisolated static func openArguments(path: String, version: String?) -> [String] {
        var args = ["open", path]
        if let version { args += ["--editor-version", version] }
        let extra = ProjectPrefs.args(for: path)
        if !extra.isEmpty { args += ["--args", extra] }
        return args
    }

    func open(_ row: ProjectRow, version: String? = nil) async {
        guard let cli else { return }
        if version == nil, !installedVersions.contains(row.project.version) {
            missingEditorFor = row
            return
        }
        await perform { try await cli.runVoid(Self.openArguments(path: row.project.path, version: version)) }
        if UserDefaults.standard.bool(forKey: "hideAfterOpen") { NSApp.hide(nil) }
    }

    /// Open a folder handed to us by Finder, the Dock or the command line. The CLI resolves the version.
    func openPath(_ path: String) async {
        guard let cli else { return }
        // Never hand an arbitrary folder to `unity open`; only real projects.
        guard Local.isUnityProject(URL(fileURLWithPath: path)) else {
            errorMessage = "\(path) is not a Unity project (no ProjectSettings/ProjectVersion.txt)."
            return
        }
        await perform { try await cli.runVoid(Self.openArguments(path: path, version: nil)) }
    }

    func cliAction(_ args: [String]) async {
        guard let cli else { return }
        await perform { try await cli.runVoid(args) }
        await refresh()
    }

    func kill(_ row: ProjectRow) async {
        guard let pid = row.pid else { return }
        Local.kill(pid: pid)
        try? await Task.sleep(for: .milliseconds(500))
        await refresh()
    }
}

/// Finder / Terminal / clipboard helpers.
@MainActor
enum Mac {
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func open(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(url)
    }

    static func openInTerminal(_ path: String) {
        NSWorkspace.shared.open([URL(fileURLWithPath: path)],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func chooseApp(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}
