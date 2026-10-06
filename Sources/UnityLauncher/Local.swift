import Foundation

struct UnityProcess: Hashable, Sendable {
    let pid: Int32
    let projectPath: String
}

/// Things the Unity CLI doesn't cover: git branch, running editors, well-known folders.
enum Local {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    // MARK: Git

    /// Branch name (or short hash when detached) of the repo containing `project`, looking up to 4 parents.
    static func gitBranch(at project: URL) -> String? {
        var dir = project.standardizedFileURL
        for _ in 0...4 {
            if let gitDir = gitDirectory(in: dir),
               let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) {
                let head = head.trimmingCharacters(in: .whitespacesAndNewlines)
                if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst("ref: refs/heads/".count)) }
                return String(head.prefix(7))
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }
            dir = parent
        }
        return nil
    }

    /// `.git` is a directory normally, or a `gitdir: <path>` file in worktrees and submodules.
    private static func gitDirectory(in dir: URL) -> URL? {
        let dotGit = dir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit }
        guard let text = try? String(contentsOf: dotGit, encoding: .utf8),
              let line = text.split(separator: "\n").first, line.hasPrefix("gitdir: ") else { return nil }
        return URL(fileURLWithPath: String(line.dropFirst("gitdir: ".count)), relativeTo: dir).standardizedFileURL
    }

    // MARK: Running editors

    static func parseUnityProcesses(_ psOutput: String) -> [UnityProcess] {
        psOutput.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.contains("Unity.app/Contents/MacOS/Unity"),
                  let space = line.firstIndex(of: " "), let pid = Int32(line[..<space]),
                  let flag = line.range(of: "-projectpath ", options: .caseInsensitive) else { return nil }
            let rest = line[flag.upperBound...]
            let value = rest.range(of: " -").map { rest[..<$0.lowerBound] } ?? rest
            return UnityProcess(pid: pid, projectPath: value.trimmingCharacters(in: .whitespaces))
        }
    }

    static func runningUnity() -> [UnityProcess] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,command="]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parseUnityProcesses(String(decoding: data, as: UTF8.self))
    }

    static func kill(pid: Int32) {
        _ = Darwin.kill(pid, SIGKILL)
    }

    // MARK: Project settings & player folders

    static func playerSettings(at project: URL) -> (company: String, product: String)? {
        let url = project.appendingPathComponent("ProjectSettings/ProjectSettings.asset")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        func value(_ key: String) -> String? {
            guard let m = text.firstMatch(of: try! Regex("(?m)^\\s*\(key): (.*)$")),
                  let v = m.output[1].substring else { return nil }
            return v.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
        }
        guard let company = value("companyName"), let product = value("productName") else { return nil }
        return (company, product)
    }

    static func persistentDataURL(company: String, product: String) -> URL {
        home.appendingPathComponent("Library/Application Support/\(company)/\(product)")
    }

    static func playerLogURL(company: String, product: String) -> URL {
        home.appendingPathComponent("Library/Logs/\(company)/\(product)/Player.log")
    }

    enum Folder: String, CaseIterable, Identifiable {
        case editorLogs = "Editor Logs"
        case crashLogs = "Crash Logs"
        case hubLogs = "Hub Logs"
        case assetStore = "Asset Store Downloads"
        case unityCache = "Unity Cache"
        case giCache = "GI Cache"

        var id: String { rawValue }

        var url: URL {
            let lib = Local.home.appendingPathComponent("Library")
            return switch self {
            case .editorLogs: lib.appendingPathComponent("Logs/Unity")
            case .crashLogs: lib.appendingPathComponent("Logs/DiagnosticReports")
            case .hubLogs: lib.appendingPathComponent("Application Support/UnityHub/logs")
            case .assetStore: lib.appendingPathComponent("Unity/Asset Store-5.x")
            case .unityCache: lib.appendingPathComponent("Unity/cache")
            case .giCache: lib.appendingPathComponent("Caches/com.unity3d.UnityEditor/GiCache")
            }
        }
    }
}

/// Per-project custom launch arguments (ULP's "Arguments" column).
enum ProjectPrefs {
    private static func key(_ path: String) -> String { "args:\(path)" }

    static func args(for path: String) -> String {
        UserDefaults.standard.string(forKey: key(path)) ?? ""
    }

    static func setArgs(_ args: String, for path: String) {
        let trimmed = args.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { UserDefaults.standard.removeObject(forKey: key(path)) }
        else { UserDefaults.standard.set(trimmed, forKey: key(path)) }
    }
}
