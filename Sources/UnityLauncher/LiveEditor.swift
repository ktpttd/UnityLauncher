import AppKit
import Observation

// MARK: Payloads of `unity status` / `unity command <name>`

struct LiveStatus: Decodable {
    let instances: [LiveInstance]
}

struct LiveInstance: Decodable, Identifiable, Hashable {
    var id: String { project }
    let port: Int
    let project: String
    let version: String?
    let pid: Int32?
    let state: String
    var isReady: Bool { state == "ready" }
}

/// `unity command <name>` wraps the Editor's return value in `data.result`.
struct CommandEnvelope<T: Decodable>: Decodable {
    let result: T?
}

struct EditorStatus: Decodable {
    let status: String?
    let compiling: Bool
    let playMode: String?
}

struct ConsolePage: Decodable {
    struct Counts: Decodable { let error: Int; let warn: Int; let log: Int }
    let entries: [ConsoleEntry]
    let counts: Counts?
}

struct ConsoleEntry: Decodable, Identifiable, Hashable {
    var id: Int { seq }
    let seq: Int
    let level: String
    let message: String
    let stackTrace: String?
}

struct EvalResult: Decodable {
    let output: String?
    let result: JSONValue?

    var display: String {
        if let result, result != .null { return result.text }
        if let out = output?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty { return out }
        return "(no result)"
    }
}

struct CommandInfo: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String?
}

/// Any JSON value, rendered as plain text (eval can return strings, numbers or objects).
enum JSONValue: Decodable, Equatable {
    case string(String), number(Double), bool(Bool), null, other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .other }
    }

    var text: String {
        switch self {
        case .string(let s): s
        case .number(let n): n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): String(b)
        case .null: "null"
        case .other: "(object — use the command box for full JSON)"
        }
    }
}

/// Splits `name --flag "two words"` into argv, honouring single and double quotes.
func splitArgs(_ line: String) -> [String] {
    var args: [String] = [], current = "", quote: Character?, inToken = false
    for ch in line {
        if let q = quote {
            if ch == q { quote = nil } else { current.append(ch) }
        } else if ch == "\"" || ch == "'" {
            quote = ch; inToken = true
        } else if ch.isWhitespace {
            if inToken { args.append(current); current = ""; inToken = false }
        } else {
            current.append(ch); inToken = true
        }
    }
    if inToken { args.append(current) }
    return args
}

extension AppState {
    nonisolated static func liveArgs(_ name: String, project: String, _ extra: [String] = []) -> [String] {
        ["command", name, "--project-path", project] + extra
    }
}

// MARK: Live tab model

@MainActor @Observable
final class LiveModel {
    var instances: [LiveInstance] = []
    var selected: String?
    var status: EditorStatus?
    var console: [ConsoleEntry] = []
    var counts: ConsolePage.Counts?
    var level = "log"
    var evalCode = "return Application.unityVersion;"
    var evalOutput = ""
    var commandLine = "get_scene_hierarchy"
    var commandOutput = ""
    var catalog: [CommandInfo] = []
    var error: String?
    var busy = false
    let cli: UnityCLI?

    init(cli: UnityCLI?) { self.cli = cli }

    private func attempt(_ op: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do { try await op(); error = nil } catch { self.error = error.localizedDescription }
    }

    func refreshInstances() async {
        guard let cli else { return }
        do {
            instances = try await cli.run(["status"], as: LiveStatus.self).instances
            error = nil
        } catch CLIError.failed(let code, _) where code == "STATUS_NO_INSTANCES" {
            instances = []
            error = nil
        } catch {
            instances = []
            self.error = error.localizedDescription
        }
        if selected == nil || !instances.contains(where: { $0.project == selected }) {
            selected = instances.first?.project
        }
    }

    /// Editor state + console. Called every few seconds while the Live tab is visible.
    func poll() async {
        guard let cli, let project = selected else { return }
        // ponytail: re-fetches the last 100 entries each poll; switch to the `since` cursor if consoles get huge.
        async let s = cli.run(AppState.liveArgs("editor_status", project: project), as: CommandEnvelope<EditorStatus>.self)
        async let c = cli.run(AppState.liveArgs("console", project: project, ["--tail", "100", "--level", level]),
                              as: CommandEnvelope<ConsolePage>.self)
        do {
            let (status, page) = try await (s, c)
            self.status = status.result
            console = page.result?.entries.reversed() ?? []
            counts = page.result?.counts
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func run(_ name: String, _ extra: [String] = []) async {
        guard let cli, let project = selected else { return }
        await attempt { try await cli.runVoid(AppState.liveArgs(name, project: project, extra)) }
        await poll()
    }

    func eval() async {
        guard let cli, let project = selected else { return }
        await attempt {
            let r = try await cli.run(AppState.liveArgs("eval", project: project, ["--code", evalCode]), as: CommandEnvelope<EvalResult>.self)
            evalOutput = r.result?.display ?? "(no result)"
        }
    }

    func runCommandLine() async {
        guard let cli, let project = selected else { return }
        let argv = splitArgs(commandLine)
        guard let name = argv.first else { return }
        await attempt {
            commandOutput = try await cli.runPretty(AppState.liveArgs(name, project: project, Array(argv.dropFirst())), field: "result")
        }
    }

    func loadCatalog() async {
        guard let cli, let project = selected else { return }
        struct Catalog: Decodable { let commands: [CommandInfo] }
        if let c = try? await cli.run(["command", "--project-path", project, "--detail", "compact"], as: Catalog.self) {
            catalog = c.commands
        }
    }

    func screenshot() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("unity-\(Int(Date().timeIntervalSince1970)).png")
        await run("screenshot", ["--output", url.path])
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }
}
