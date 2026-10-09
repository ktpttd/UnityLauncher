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
    var state: State = .running {
        didSet { if state != .running, finishedAt == nil { finishedAt = Date() } }
    }
    let startedAt = Date()
    var finishedAt: Date?
    /// One-line result shown under the title, e.g. a build's output and size.
    var summary: String?
    /// Build output to reveal in Finder.
    var output: URL?
    /// Project a build task built, for its Build Report.
    var project: String?
    /// Lines from the build log explaining a failure.
    var failureDetails: [String] = []
    /// iOS build made with the Simulator SDK: runs on simulators, not devices.
    var simulatorSDK = false
    /// Build Profile the build used (to rebuild it for the simulator).
    var profile: String?
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
    func runTask(_ title: String, _ args: [String], refreshAfter: Bool = true, environment: [String: String] = [:]) -> TaskItem {
        let item = TaskItem(title: title)
        tasks.insert(item, at: 0)
        showTasks = true
        guard let cli else {
            item.state = .failed(CLIError.notFound.localizedDescription)
            return item
        }
        item.task = Task {
            do {
                for try await f in cli.stream(args, environment: environment) { item.apply(f) }
                if item.state == .running { item.state = .succeeded }
            } catch {
                if item.state == .running { item.state = .failed(error.localizedDescription) }
            }
            if args.first == "build", args.count > 1 {
                let project = URL(fileURLWithPath: args[1])
                // Unity exits 0 when player scripts don't compile, so the CLI reports success with no build.
                let checkSuccess = item.state == .succeeded && args.contains("--output-path")
                let errors = await Task.detached { () -> [String] in
                    guard let log = BuildErrors.latestLog(project: project)
                        .flatMap({ try? Data(contentsOf: $0) }).map({ String(decoding: $0, as: UTF8.self) }),
                          !checkSuccess || !log.contains("Build Finished, Result: Success") else { return [] }
                    return BuildErrors.find(in: log)
                }.value
                if checkSuccess, !errors.isEmpty { item.state = .failed("Unity exited without building the player") }
                if case .failed = item.state { item.failureDetails = errors }
            }
            if item.state == .succeeded, args.first == "build",
               let i = args.firstIndex(of: "--output-path"), i + 1 < args.count {
                let url = URL(fileURLWithPath: args[i + 1])
                let size = await Task.detached { Local.diskSize(url) }.value
                item.output = url
                item.project = args[1]
                item.summary = "Output: \(url.lastPathComponent)" + (size.map { " · " + formatBytes($0) } ?? "")
            }
            Notify.taskFinished(item)
            if refreshAfter { await refresh() }
        }
        return item
    }
}

/// "5s", "1m 39s", "1h 2m 5s".
func formatDuration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded()), h = s / 3600, m = s % 3600 / 60, sec = s % 60
    return h > 0 ? "\(h)h \(m)m \(sec)s" : m > 0 ? "\(m)m \(sec)s" : "\(sec)s"
}

/// Folder holding a build: the output itself if it's a plain folder (iOS, WebGL), else its parent
/// (.apk, .exe, and .app bundles, which would launch if opened).
func buildOutputFolder(_ output: URL) -> URL {
    let v = try? output.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    return v?.isDirectory == true && v?.isPackage != true ? output : output.deletingLastPathComponent()
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

    /// Unity's `BuildTarget` enum value, as stored in a Build Profile's `m_BuildTarget`.
    init?(unityID: Int) {
        switch unityID {
        case 2: self = .macOS
        case 9: self = .iOS
        case 13: self = .android
        case 19: self = .windows
        case 20: self = .webGL
        case 24: self = .linux
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .macOS: "macOS"; case .windows: "Windows"; case .linux: "Linux"
        case .iOS: "iOS"; case .android: "Android"; case .webGL: "WebGL"
        }
    }
    /// `unity build --list-targets`: everything except desktop needs `--profile` or `--execute-method`.
    var needsProfile: Bool { ![.macOS, .windows, .linux].contains(self) }

    func defaultOutput(project: String, product: String, appBundle: Bool = false) -> String {
        let name = product.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-")
        let dir = "\(project)/Builds/\(rawValue)"
        return switch self {
        case .macOS: "\(dir)/\(name).app"
        case .windows: "\(dir)/\(name).exe"
        case .linux: "\(dir)/\(name).x86_64"
        case .android: "\(dir)/\(name).\(appBundle ? "aab" : "apk")"
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
