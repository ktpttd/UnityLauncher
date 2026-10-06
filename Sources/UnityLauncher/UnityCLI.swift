import Foundation

enum CLIError: LocalizedError, Equatable {
    case notFound
    case failed(code: String, message: String)
    case badOutput(String)
    case exited(Int32, String)

    var errorDescription: String? {
        switch self {
        case .notFound: "Unity CLI not found. Install it or set its path in Settings."
        case .failed(_, let message): message
        case .badOutput(let out): "Unexpected Unity CLI output:\n\(out)"
        case .exited(let code, let stderr): "Unity CLI exited with code \(code)." + (stderr.isEmpty ? "" : "\n\(stderr)")
        }
    }
}

/// One line of `--format ndjson` output.
struct Frame: Decodable, Sendable {
    let type: String
    let message: String?
    let pct: Double?
    let success: Bool?
    let errors: [CLIErrorItem]?
}

/// Thin wrapper over the `unity` binary. Every call is `unity --no-banner --non-interactive --format <fmt> <args>`.
struct UnityCLI: Sendable {
    let executable: URL

    static let defaultCandidates = ["~/.unity/bin/unity", "/opt/homebrew/bin/unity", "/usr/local/bin/unity"]

    /// GUI apps don't inherit the shell PATH, so look in the CLI's known install locations.
    static func locate(override: String?, candidates: [String] = defaultCandidates) -> URL? {
        let paths = [override].compactMap { $0 }.filter { !$0.isEmpty } + candidates
        return paths
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static let environment = ProcessInfo.processInfo.environment.merging([
        "UNITY_NO_CONSENT_PROMPT": "1",
        "UNITY_NO_UPDATE_CHECK": "1",
        "UNITY_NO_PAGER": "1",
    ]) { _, new in new }

    private func makeProcess(_ args: [String], format: String) -> Process {
        let p = Process()
        p.executableURL = executable
        p.arguments = ["--no-banner", "--non-interactive", "--format", format] + args
        p.environment = Self.environment
        p.standardInput = FileHandle.nullDevice
        return p
    }

    // MARK: Request / response

    func run<T: Decodable>(_ args: [String], as: T.Type = T.self) async throws -> T {
        guard let data = try await envelope(args, as: T.self).data else { throw CLIError.badOutput("missing data") }
        return data
    }

    func runVoid(_ args: [String]) async throws {
        _ = try await envelope(args, as: Ignored.self)
    }

    private struct Ignored: Decodable { init(from decoder: Decoder) {} }

    private func envelope<T: Decodable>(_ args: [String], as: T.Type) async throws -> Envelope<T> {
        let (out, err, status) = try await execute(makeProcess(args, format: "json"))
        return try Self.decode(out, stderr: err, status: status)
    }

    static func decode<T: Decodable>(_ out: Data, stderr: Data, status: Int32) throws -> Envelope<T> {
        // Tolerate stray notices before the JSON document.
        guard let start = out.firstIndex(of: UInt8(ascii: "{")) else {
            throw CLIError.exited(status, String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let env: Envelope<T>
        do { env = try JSONDecoder().decode(Envelope<T>.self, from: out[start...]) }
        catch { throw CLIError.badOutput(String(decoding: out.prefix(500), as: UTF8.self)) }
        guard env.success else {
            let e = env.errors.first
            throw CLIError.failed(code: e?.code ?? "UNKNOWN", message: e?.message ?? "Unity CLI reported a failure.")
        }
        return env
    }

    private func execute(_ p: Process) async throws -> (Data, Data, Int32) {
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { throw CLIError.notFound }
        // Drain both pipes concurrently so a chatty stderr can't block stdout.
        async let o = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
        async let e = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
        let result = await (o, e)
        p.waitUntilExit()
        return (result.0, result.1, p.terminationStatus)
    }

    // MARK: Streaming (install, build, test…)

    /// Yields every ndjson frame, including the final `result`. Throws only if the process
    /// dies without emitting a `result` frame. Cancelling the consumer terminates the process.
    func stream(_ args: [String]) -> AsyncThrowingStream<Frame, Error> {
        let p = makeProcess(args, format: "ndjson")
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        return AsyncThrowingStream { cont in
            let task = Task.detached {
                do {
                    do { try p.run() } catch { throw CLIError.notFound }
                    var gotResult = false
                    for try await line in out.fileHandleForReading.bytes.lines {
                        guard let start = line.firstIndex(of: "{"),
                              let frame = try? JSONDecoder().decode(Frame.self, from: Data(line[start...].utf8))
                        else { continue }
                        if frame.type == "result" { gotResult = true }
                        cont.yield(frame)
                    }
                    p.waitUntilExit()
                    if !gotResult && p.terminationStatus != 0 {
                        throw CLIError.exited(p.terminationStatus, "")
                    }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in
                task.cancel()
                if p.isRunning { p.terminate() }
            }
        }
    }

    // MARK: Fire and forget (open, build run)

    func spawn(_ args: [String]) throws -> Process {
        let p = makeProcess(args, format: "json")
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw CLIError.notFound }
        return p
    }
}
