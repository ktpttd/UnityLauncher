import Foundation

/// Install-and-run for Android builds, using the SDK tools bundled with Unity's Android module.
enum Android {
    struct Device: Equatable, Identifiable {
        var id: String { serial }
        let serial: String
        let model: String
    }

    /// Devices ready for adb from `adb devices [-l]` (skips "offline" / "unauthorized"), with model names.
    static func deviceList(fromADBOutput output: String) -> [Device] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2, parts[1] == "device" else { return nil }
            let model = parts.first { $0.hasPrefix("model:") }.map { $0.dropFirst("model:".count).replacingOccurrences(of: "_", with: " ") }
            return Device(serial: String(parts[0]), model: model ?? String(parts[0]))
        }
    }

    static func devices(fromADBOutput output: String) -> [String] {
        deviceList(fromADBOutput: output).map(\.serial)
    }

    /// Package name from `aapt dump badging`.
    static func package(fromBadging output: String) -> String? {
        output.firstMatch(of: /package: name='([^']+)'/).map { String($0.1) }
    }

    /// Newest build-tools binary from an installed editor's Android SDK.
    static func buildTool(_ name: String, editorLocations: [String]) -> URL? {
        for location in editorLocations {
            let dir = URL(fileURLWithPath: location).deletingLastPathComponent()
                .appendingPathComponent("PlaybackEngines/AndroidPlayer/SDK/build-tools")
            let versions = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            if let v = versions.first(where: { FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent("\($0)/\(name)").path) }) {
                return dir.appendingPathComponent("\(v)/\(name)")
            }
        }
        return nil
    }
}

enum Shell {
    /// Runs a tool off the main thread; returns its exit code and combined stdout/stderr.
    static func run(_ tool: URL, _ args: [String], environment: [String: String] = [:]) async -> (status: Int32, output: String) {
        await Task.detached {
            let p = Process()
            p.executableURL = tool
            p.arguments = args
            p.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            guard (try? p.run()) != nil else { return (-1, "Couldn't run \(tool.lastPathComponent).") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
    }
}

struct StepError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension AppState {
    /// A Tasks-panel entry for work that isn't a Unity CLI command.
    @discardableResult
    func runSteps(_ title: String, _ steps: @escaping @MainActor (TaskItem) async throws -> Void) -> TaskItem {
        let item = TaskItem(title: title)
        tasks.insert(item, at: 0)
        showTasks = true
        item.task = Task {
            do {
                try await steps(item)
                if item.state == .running { item.state = .succeeded }
            } catch {
                if item.state == .running { item.state = .failed(error.localizedDescription) }
            }
            Notify.taskFinished(item)
        }
        return item
    }

    /// `adb install -r` on `device` (or the first connected one), then launch the app.
    func installOnDevice(_ apk: URL, device chosen: Android.Device? = nil) {
        let editorLocations = editors.map(\.location)
        runSteps("Install on \(chosen?.model ?? "Android device")") { item in
            guard let adbPath = Local.adbPath(editorLocations: editorLocations) else {
                throw StepError(message: "adb not found. Install Android Build Support for a Unity editor.")
            }
            let adb = URL(fileURLWithPath: adbPath)
            let serial: String
            if let chosen { serial = chosen.serial } else {
                guard let first = Android.devices(fromADBOutput: await Shell.run(adb, ["devices"]).output).first else {
                    throw StepError(message: "No Android device connected. Plug one in and allow USB debugging.")
                }
                serial = first
            }
            let device = serial
            item.log.append("Device \(chosen.map { "\($0.model) (\($0.serial))" } ?? serial)")
            item.log.append("Installing…")
            let install = await Shell.run(adb, ["-s", device, "install", "-r", apk.path])
            let lines = install.output.split(separator: "\n").map(String.init)
            item.log.append(contentsOf: lines.suffix(5))
            guard install.status == 0, install.output.contains("Success") else {
                throw StepError(message: lines.last { $0.contains("Failure") || $0.contains("error") } ?? "adb install failed.")
            }
            guard let aapt = Android.buildTool("aapt", editorLocations: editorLocations),
                  let package = Android.package(fromBadging: await Shell.run(aapt, ["dump", "badging", apk.path]).output) else {
                item.log.append("Installed. Couldn't read the package name, so it wasn't launched.")
                return
            }
            item.log.append("Launching \(package)")
            _ = await Shell.run(adb, ["-s", device, "shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1"])
        }
    }
}
