import SwiftUI

/// Unity's "Build Report" block from Editor.log / `unity build` logs (ULP's Build Report tab).
struct BuildReport: Equatable {
    struct Stat: Hashable, Identifiable {
        var id: String { category }
        let category: String
        let size: String
        let percent: String?
    }

    struct Item: Hashable, Identifiable {
        var id: String { path }
        let size: String
        let percent: String
        let path: String
    }

    var stats: [Stat] = []
    var items: [Item] = []

    struct Found: Equatable {
        let source: URL
        let report: BuildReport
    }

    /// Every report in a log, oldest first.
    static func parseAll(_ log: String) -> [BuildReport] {
        enum Mode { case none, stats, items }
        var reports: [BuildReport] = []
        var current: BuildReport?
        var mode = Mode.none
        for raw in log.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("Uncompressed usage by category") {
                current = BuildReport(); mode = .stats; continue
            }
            if line.hasPrefix("Used Assets and files from the Resources folder") {
                mode = current == nil ? .none : .items; continue
            }
            if mode == .items, line.hasPrefix("----------"), let c = current {
                reports.append(c); current = nil; mode = .none; continue
            }
            switch mode {
            case .stats:
                // "Textures               6.9 mb\t 47.2%"  or  "Complete build size    40.4 mb"
                let parts = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if let m = parts.first?.firstMatch(of: /^(.+?)\s{2,}(\S+ \S+)$/) {
                    current?.stats.append(Stat(category: String(m.1), size: String(m.2), percent: parts.count > 1 ? parts[1] : nil))
                }
            case .items:
                // "3.0 mb\t 20.7% Assets/Textures/Big Background.png"
                if let m = line.firstMatch(of: /^(\S+ \S+)\t\s*([\d.]+%)\s+(.+)$/) {
                    current?.items.append(Item(size: String(m.1), percent: String(m.2), path: String(m.3)))
                }
            case .none:
                break
            }
        }
        return reports
    }

    /// Latest report for a project: newest `Logs/build-*.log` (CLI builds) or the shared Editor.log
    /// when it belongs to this project.
    static func latest(project: URL,
                       editorLog: URL = Local.Folder.editorLogs.url.appendingPathComponent("Editor.log")) -> Found? {
        let fm = FileManager.default
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let buildLogs = (try? fm.contentsOfDirectory(at: project.appendingPathComponent("Logs"), includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.lastPathComponent.hasPrefix("build-") && $0.pathExtension == "log" } ?? []
        for url in (buildLogs + [editorLog]).sorted(by: { modified($0) > modified($1) }) {
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            if url == editorLog, !text.contains(project.path) { continue }
            if let report = parseAll(text).last { return Found(source: url, report: report) }
        }
        return nil
    }
}

struct BuildReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let row: ProjectRow
    @State private var found: BuildReport.Found?
    @State private var loaded = false
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Build Report — \(row.project.title)").font(.headline)
                Spacer()
                if let found { Button("Show Log") { Mac.reveal(found.source.path) } }
            }
            if let found {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                    ForEach(found.report.stats) { s in
                        GridRow {
                            Text(s.category).fontWeight(s.percent == nil ? .bold : .regular)
                            Text(s.size).monospacedDigit()
                            Text(s.percent ?? "").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .font(.callout)
                TextField("Filter assets", text: $filter).textFieldStyle(.roundedBorder)
                let items = found.report.items.filter { filter.isEmpty || $0.path.localizedCaseInsensitiveContains(filter) }
                Table(items) {
                    TableColumn("Size", value: \.size).width(80)
                    TableColumn("%", value: \.percent).width(60)
                    TableColumn("Asset", value: \.path)
                }
                .contextMenu(forSelectionType: BuildReport.Item.ID.self) { _ in } primaryAction: { ids in
                    if let path = ids.first { Mac.reveal(row.project.path + "/" + path) }
                }
                Text("Source: \(found.source.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else if loaded {
                ContentUnavailableView("No build report yet", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Build the project (right-click → Build…) and the report appears here."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding()
        .frame(width: 720, height: 560)
        .task {
            let project = URL(fileURLWithPath: row.project.path)
            found = await Task.detached { BuildReport.latest(project: project) }.value
            loaded = true
        }
    }
}
