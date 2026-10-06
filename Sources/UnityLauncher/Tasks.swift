import Foundation
import Observation

/// A long-running CLI command (install, build, test, upgrade…) shown in the Tasks panel.
@MainActor @Observable
final class TaskItem: Identifiable {
    enum State: Equatable { case running, succeeded, failed(String) }

    let id = UUID()
    let title: String
    var log: [String] = []
    var pct: Double?
    var state: State = .running
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var process: Process?

    init(title: String) { self.title = title }

    func apply(_ f: Frame) {
        let line: String? = if let code = f.code {
            // Finding: "error CONFLICT_MARKERS Assets/b.meta: message"
            [f.severity, code, f.path].compactMap { $0 }.joined(separator: " ") + (f.message.map { ": \($0)" } ?? "")
        } else {
            f.message
        }
        if let line, !line.isEmpty {
            log.append(line)
            if log.count > 1000 { log.removeFirst(log.count - 1000) } // ponytail: capped buffer, write to file if full logs matter
        }
        if let p = f.pct { pct = p }
        if f.type == "result" {
            state = f.success == true ? .succeeded : .failed(f.errors?.first?.message ?? "Failed")
        }
    }

    func stop() {
        guard state == .running else { return }
        state = .failed("Stopped")
        task?.cancel()
        process?.terminate()
    }
}

extension AppState {
    /// Streams `args` as ndjson into a new TaskItem.
    @discardableResult
    func runTask(_ title: String, _ args: [String], refreshAfter: Bool = true) -> TaskItem {
        let item = TaskItem(title: title)
        tasks.insert(item, at: 0)
        showTasks = true
        guard let cli else {
            item.state = .failed(CLIError.notFound.localizedDescription)
            return item
        }
        item.task = Task {
            do {
                for try await f in cli.stream(args) { item.apply(f) }
                if item.state == .running { item.state = .succeeded }
            } catch {
                if item.state == .running { item.state = .failed(error.localizedDescription) }
            }
            if refreshAfter { await refresh() }
        }
        return item
    }

    /// Called on quit: servers would otherwise outlive the app and keep their port open.
    /// Installs and builds are left to finish.
    func stopServers() {
        for item in tasks where item.process != nil { item.stop() }
    }

    /// Starts a process that keeps running until stopped (e.g. the WebGL server of `build run`).
    func runServer(_ title: String, _ args: [String]) {
        let item = TaskItem(title: title)
        tasks.insert(item, at: 0)
        showTasks = true
        guard let cli else {
            item.state = .failed(CLIError.notFound.localizedDescription)
            return
        }
        do {
            let p = try cli.spawn(args)
            item.process = p
            item.log.append("Running. Press Stop to shut it down.")
            p.terminationHandler = { p in
                let status = p.terminationStatus
                Task { @MainActor in
                    if item.state == .running { item.state = status == 0 ? .succeeded : .failed("Exited with code \(status)") }
                }
            }
        } catch {
            item.state = .failed(error.localizedDescription)
        }
    }
}

struct ProjectSize: Decodable {
    struct Entry: Decodable { let folder: String; let bytes: Int64 }
    let total: Int64
    let breakdown: [Entry]

    var summary: String {
        func fmt(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
        return (["Total: \(fmt(total))"] + breakdown.prefix(6).map { "\($0.folder): \(fmt($0.bytes))" })
            .joined(separator: "\n")
    }
}

struct Template: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let displayName: String
}

/// Desktop targets the CLI can build without a custom method or Build Profile.
enum BuildTarget: String, CaseIterable, Identifiable {
    case macOS = "StandaloneOSX", windows = "StandaloneWindows64", linux = "StandaloneLinux64"

    var id: String { rawValue }
    var label: String {
        switch self { case .macOS: "macOS"; case .windows: "Windows"; case .linux: "Linux" }
    }
    private var ext: String {
        switch self { case .macOS: ".app"; case .windows: ".exe"; case .linux: ".x86_64" }
    }

    func defaultOutput(project: String, product: String) -> String {
        "\(project)/Builds/\(rawValue)/\(product)\(ext)"
    }
}

struct InfoMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
