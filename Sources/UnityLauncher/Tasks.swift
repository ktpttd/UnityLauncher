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

    init(title: String) { self.title = title }

    func apply(_ f: Frame) {
        let line: String? = if let code = f.code {
            // Finding: "error CONFLICT_MARKERS Assets/b.meta: message"
            [f.severity, code, f.path].compactMap { $0 }.joined(separator: " ") + (f.text.map { ": \($0)" } ?? "")
        } else {
            f.text
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

/// Build targets offered in the Build sheet. Only desktop targets build without a Build Profile.
enum BuildTarget: String, CaseIterable, Identifiable {
    case macOS = "StandaloneOSX", windows = "StandaloneWindows64", linux = "StandaloneLinux64"
    case iOS, android = "Android", webGL = "WebGL"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .macOS: "macOS"; case .windows: "Windows"; case .linux: "Linux"
        case .iOS: "iOS"; case .android: "Android"; case .webGL: "WebGL"
        }
    }
    /// `unity build --list-targets`: everything except desktop needs `--profile` or `--execute-method`.
    var needsProfile: Bool { ![.macOS, .windows, .linux].contains(self) }

    func defaultOutput(project: String, product: String) -> String {
        let name = product.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        let dir = "\(project)/Builds/\(rawValue)"
        return switch self {
        case .macOS: "\(dir)/\(name).app"
        case .windows: "\(dir)/\(name).exe"
        case .linux: "\(dir)/\(name).x86_64"
        case .android: "\(dir)/\(name).apk"
        case .iOS, .webGL: dir // Xcode project / web folder
        }
    }

    static func arguments(project: String, target: BuildTarget, profile: String?, output: String, allowDirty: Bool) -> [String] {
        var args = ["build", project, "--output-path", output]
        args += profile.map { ["--profile", $0] } ?? ["--target", target.rawValue]
        if allowDirty { args.append("--allow-dirty-build") }
        return args
    }
}

struct InfoMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
