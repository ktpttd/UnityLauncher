import Foundation

struct AndroidSigning: Equatable {
    let keystore: URL
    let alias: String
    let custom: Bool
}

struct UnityProcess: Hashable, Sendable {
    let pid: Int32
    /// Everything after `-projectPath `. ps prints argv unquoted, so the path's end is ambiguous;
    /// callers match it against known project paths.
    let argsTail: String
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
                  !line.contains("AssetImportWorker"), // child workers share -projectPath with the editor
                  let space = line.firstIndex(of: " "), let pid = Int32(line[..<space]),
                  let flag = line.range(of: "-projectpath ", options: .caseInsensitive) else { return nil }
            return UnityProcess(pid: pid, argsTail: line[flag.upperBound...].trimmingCharacters(in: .whitespaces))
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

    // MARK: Finder / command-line integration

    static func isUnityProject(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("ProjectSettings/ProjectVersion.txt").path)
    }

    /// Live control needs the `com.unity.pipeline` package in the project's manifest.
    static func hasPipeline(_ project: URL) -> Bool {
        let manifest = try? String(contentsOf: project.appendingPathComponent("Packages/manifest.json"), encoding: .utf8)
        return manifest?.contains("\"com.unity.pipeline\"") ?? false
    }

    /// Build Profile assets anywhere under Assets. (`unity build --list-profiles` only looks in
    /// "Assets/Settings/Build Profiles", but Unity lets them live anywhere.)
    static func buildProfiles(in project: URL) -> [BuildProfile] {
        let assets = project.appendingPathComponent("Assets")
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: assets, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var found: [BuildProfile] = []
        for case let url as URL in walker where url.pathExtension == "asset" {
            // Profiles are small YAML files; skip big binary assets without reading them.
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, (v.fileSize ?? 0) < 512_000,
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let head = String(decoding: (try? handle.read(upToCount: 4096)) ?? Data(), as: UTF8.self)
            try? handle.close()
            // BuildProfile is built-in class 15003 of UnityEditor.dll; older saves leave the class identifier empty.
            let isProfile = head.contains("UnityEditor.Build.Profile.BuildProfile")
                || head.contains("fileID: 15003, guid: 0000000000000000e000000000000000")
            guard isProfile, head.contains("m_BuildTarget:"),
                  let name = head.firstMatch(of: /m_Name: (.+)/)?.1 else { continue }
            let target = head.firstMatch(of: /m_BuildTarget: (\d+)/).flatMap { Int($0.1) }.flatMap(BuildTarget.init(unityID:))
            let relative = "Assets" + url.standardizedFileURL.path.dropFirst(assets.standardizedFileURL.path.count)
            // The App Bundle flag sits at the end of the file, past the header read above.
            let appBundle = target == .android
                && ((try? String(contentsOf: url, encoding: .utf8))?.contains("m_BuildAppBundle: 1") ?? false)
            found.append(BuildProfile(profile: String(name).trimmingCharacters(in: .whitespaces), path: relative,
                                      target: target, appBundle: appBundle))
        }
        return found.sorted { $0.profile.localizedCaseInsensitiveCompare($1.profile) == .orderedAscending }
    }

    /// Total size of a file, or of every file inside a folder/bundle. nil if it doesn't exist.
    static func diskSize(_ url: URL) -> Int64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        guard isDir.boolValue else {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            if let v = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true {
                total += Int64(v.fileSize ?? 0)
            }
        }
        return total
    }

    /// Android keystore + alias a build will sign with: the Build Profile's override if it has one,
    /// else Player Settings. `custom == false` means Unity's debug keystore (no password needed).
    static func androidSigning(project: URL, profile: String?) -> AndroidSigning? {
        func read(_ relative: String) -> String {
            (try? String(contentsOf: project.appendingPathComponent(relative), encoding: .utf8)) ?? ""
        }
        let sources = [profile.map(read) ?? "", read("ProjectSettings/ProjectSettings.asset")]
        func value(_ key: String) -> String? {
            for text in sources {
                // Profile overrides look like  - line: '|   Key: ''value'''  and Player Settings like  Key: 'value'
                if let m = text.firstMatch(of: try! Regex<(Substring, Substring)>("\(key): (.*)")) {
                    return m.output.1.trimmingCharacters(in: CharacterSet(charactersIn: "' "))
                }
            }
            return nil
        }
        guard let name = value("AndroidKeystoreName"), !name.isEmpty else { return nil }
        let keystore = name.hasPrefix("{inproject}: ")
            ? project.appendingPathComponent(String(name.dropFirst("{inproject}: ".count)))
            : URL(fileURLWithPath: NSString(string: name).expandingTildeInPath)
        return AndroidSigning(keystore: keystore, alias: value("AndroidKeyaliasName") ?? "",
                              custom: value("androidUseCustomKeystore") == "1")
    }

    /// ULP-compatible `-projectPath <path>`, or a bare argument that is a Unity project folder.
    static func projectPath(fromArguments args: [String]) -> String? {
        let rest = Array(args.dropFirst())
        if let i = rest.firstIndex(where: { $0.caseInsensitiveCompare("-projectPath") == .orderedSame }), i + 1 < rest.count {
            return rest[i + 1]
        }
        return rest.first { !$0.hasPrefix("-") && isUnityProject(URL(fileURLWithPath: $0)) }
    }

    /// Unity's bundled Android SDK adb (newest editor first), else a system adb.
    static func adbPath(editorLocations: [String],
                        fallbacks: [String] = ["~/Library/Android/sdk/platform-tools/adb", "/opt/homebrew/bin/adb", "/usr/local/bin/adb"]) -> String? {
        let bundled = editorLocations.map {
            URL(fileURLWithPath: $0).deletingLastPathComponent()
                .appendingPathComponent("PlaybackEngines/AndroidPlayer/SDK/platform-tools/adb").path
        }
        return (bundled + fallbacks.map { NSString(string: $0).expandingTildeInPath })
            .first { FileManager.default.isExecutableFile(atPath: $0) }
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

    /// Apple Developer Team ID used to sign this project's iOS builds for a device.
    static func teamID(for path: String) -> String {
        UserDefaults.standard.string(forKey: "team:\(path)") ?? ""
    }

    static func setTeamID(_ id: String, for path: String) {
        if id.isEmpty { UserDefaults.standard.removeObject(forKey: "team:\(path)") }
        else { UserDefaults.standard.set(id, forKey: "team:\(path)") }
    }

    static func setArgs(_ args: String, for path: String) {
        let trimmed = args.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { UserDefaults.standard.removeObject(forKey: key(path)) }
        else { UserDefaults.standard.set(trimmed, forKey: key(path)) }
    }
}
