import Foundation

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
