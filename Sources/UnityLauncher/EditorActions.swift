import AppKit

enum ReleaseStream: String, CaseIterable, Identifiable {
    case all = "All", lts = "LTS", tech = "Tech", beta = "Beta", alpha = "Alpha"
    var id: String { rawValue }
}

extension AppState {
    var filteredReleases: [Release] {
        let q = releaseSearch.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? releases : releases.filter { $0.version.localizedCaseInsensitiveContains(q) }
    }

    nonisolated static func releaseArguments(stream: ReleaseStream) -> [String] {
        ["releases", "--limit", "200"] + (stream == .all ? [] : ["--stream", stream.rawValue.lowercased()])
    }

    nonisolated static func moduleAddArguments(version: String, modules: [String]) -> [String] {
        ["editors", "module", "add", version] + modules.flatMap { ["--module", $0] } + ["--accept-eula"]
    }

    func loadReleases() async {
        guard let cli else { return }
        releasesLoading = true
        defer { releasesLoading = false }
        await perform { releases = try await cli.run(Self.releaseArguments(stream: releaseStream), as: [Release].self) }
    }

    func modules(for version: String) async -> [ModuleInfo] {
        guard let cli else { return [] }
        do { return try await cli.run(["modules", "list", version], as: [ModuleInfo].self) }
        catch { errorMessage = error.localizedDescription; return [] }
    }
}

extension AppState {
    func doctor() async {
        guard let cli else { return }
        await perform { report = InfoMessage(title: "Unity Doctor", message: try await cli.runPretty(["doctor"])) }
    }

    /// Opens Terminal with `adb logcat -s Unity` via a .command file (no Automation permission needed).
    func adbLogcat() {
        guard let adb = Local.adbPath(editorLocations: editors.map(\.location)) else {
            errorMessage = "adb not found. Install Android Build Support for a Unity editor, or the Android SDK."
            return
        }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("unity-logcat.command")
        let quoted = "'" + adb.replacingOccurrences(of: "'", with: "'\\''") + "'"
        do {
            try "#!/bin/sh\nexec \(quoted) logcat -s Unity\n".write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
