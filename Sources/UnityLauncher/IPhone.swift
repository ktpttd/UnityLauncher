import AppKit

/// Install-and-run for iOS builds without opening Xcode: xcodebuild signs, devicectl installs and launches.
enum IPhone {
    struct Device: Equatable, Identifiable {
        var id: String { udid }
        let udid: String
        let name: String
    }

    /// Paired physical iOS devices from `devicectl list devices --json-output`, connected ones first.
    static func devices(fromDevicectlJSON data: Data) -> [Device] {
        struct Root: Decodable {
            struct Result: Decodable { let devices: [Entry] }
            let result: Result
        }
        struct Entry: Decodable {
            struct Hardware: Decodable { let udid: String?; let platform: String?; let reality: String? }
            struct Properties: Decodable { let name: String? }
            struct Connection: Decodable { let pairingState: String?; let tunnelState: String? }
            let hardwareProperties: Hardware
            let deviceProperties: Properties?
            let connectionProperties: Connection?
        }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return [] }
        return root.result.devices
            .filter { $0.hardwareProperties.reality == "physical" && $0.hardwareProperties.platform == "iOS"
                && $0.connectionProperties?.pairingState == "paired" }
            .sorted { ($0.connectionProperties?.tunnelState == "connected" ? 0 : 1) < ($1.connectionProperties?.tunnelState == "connected" ? 0 : 1) }
            .compactMap { e in e.hardwareProperties.udid.map { Device(udid: $0, name: e.deviceProperties?.name ?? $0) } }
    }

    struct Simulator: Equatable, Identifiable {
        var id: String { udid }
        let udid: String
        let name: String
        let runtime: String
        let booted: Bool
    }

    /// Available iOS simulators from `simctl list devices available -j`: booted first, newest iOS first.
    static func simulators(fromSimctlJSON data: Data) -> [Simulator] {
        struct Root: Decodable { let devices: [String: [Entry]] }
        struct Entry: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool? }
        guard let root = try? JSONDecoder().decode(Root.self, from: data) else { return [] }
        var sims: [Simulator] = []
        for key in root.devices.keys.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
            guard let r = key.range(of: "SimRuntime.iOS-") else { continue }
            let runtime = "iOS " + key[r.upperBound...].replacingOccurrences(of: "-", with: ".")
            for e in root.devices[key] ?? [] where e.isAvailable != false {
                sims.append(Simulator(udid: e.udid, name: e.name, runtime: runtime, booted: e.state == "Booted"))
            }
        }
        // Stable: booted ones move to the front, everything else keeps newest-runtime order.
        return sims.filter(\.booted) + sims.filter { !$0.booted }
    }

    struct Team: Equatable, Identifiable {
        let id: String
        let name: String
    }

    /// Teams of the Apple accounts signed into Xcode (Settings → Accounts), first-seen order.
    static func teams(fromXcodeDefaults defaults: [String: Any]) -> [Team] {
        var teams: [Team] = []
        for account in defaults.keys.sorted() {
            for entry in defaults[account] as? [[String: Any]] ?? [] {
                guard let id = entry["teamID"] as? String, isValidTeamID(id), !teams.contains(where: { $0.id == id }) else { continue }
                teams.append(Team(id: id, name: entry["teamName"] as? String ?? id))
            }
        }
        return teams
    }

    static var xcodeTeams: [Team] {
        teams(fromXcodeDefaults: UserDefaults(suiteName: "com.apple.dt.Xcode")?.dictionary(forKey: "IDEProvisioningTeamByIdentifier") ?? [:])
    }

    /// Apple Developer Team IDs are 10 uppercase letters/digits.
    static func isValidTeamID(_ id: String) -> Bool {
        id.wholeMatch(of: /[A-Z0-9]{10}/) != nil
    }

    /// The configuration Xcode's Run uses: the scheme's LaunchAction (Unity sets ReleaseForRunning).
    /// Unity's Debug configuration overflows the stack at launch when run outside Xcode.
    static func runConfiguration(buildFolder: URL) -> String {
        let fm = FileManager.default
        let projects = ((try? fm.contentsOfDirectory(at: buildFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "xcodeproj" }
        for project in projects {
            let schemes = project.appendingPathComponent("xcshareddata/xcschemes")
            let files = ((try? fm.contentsOfDirectory(at: schemes, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "xcscheme" }
                .sorted { $0.lastPathComponent == "Unity-iPhone.xcscheme" && $1.lastPathComponent != "Unity-iPhone.xcscheme" }
            for file in files {
                if let text = try? String(contentsOf: file, encoding: .utf8),
                   let m = text.firstMatch(of: /<LaunchAction\s+buildConfiguration\s*=\s*"([^"]+)"/) {
                    return String(m.1)
                }
            }
        }
        return "Release"
    }

    /// Device builds are signed with the team. Simulator builds (pass the simulator's udid) need no
    /// signing and target that simulator's architecture only.
    static func xcodebuildArguments(project: URL, team: String?, derivedData: URL, configuration: String,
                                    simulator: String? = nil) -> [String] {
        var args = [project.pathExtension == "xcworkspace" ? "-workspace" : "-project", project.path,
                    "-scheme", "Unity-iPhone", "-configuration", configuration,
                    "-destination", simulator.map { "platform=iOS Simulator,id=\($0)" } ?? "generic/platform=iOS",
                    "-derivedDataPath", derivedData.path, "-quiet"]
        if simulator != nil { args += ["ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO"] }
        else { args += ["-allowProvisioningUpdates"] + (team.map { ["DEVELOPMENT_TEAM=\($0)"] } ?? []) }
        return args + ["build"]
    }

    /// Compiler, signing and link errors from xcodebuild output, deduplicated, at most four. A library
    /// built only for devices (the usual reason a simulator build fails to link) is listed first: ld
    /// prints it after the generic "linker command failed".
    static func errors(fromXcodebuild output: String) -> [String] {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let deviceOnly = lines.filter { $0.contains("but linking in object file") }
        let other = lines.filter { $0.hasPrefix("error:") || $0.contains(": error:") }
        var found: [String] = []
        for line in deviceOnly + other where !found.contains(line) {
            found.append(line)
            if found.count == 4 { break }
        }
        return found
    }

    /// Beside the build folder, not in it: keeps GBs of Xcode cache out of the output size and safe
    /// from Unity replacing the folder on the next build.
    static func derivedData(for buildFolder: URL) -> URL {
        buildFolder.deletingLastPathComponent().appendingPathComponent(buildFolder.lastPathComponent + "-DerivedData")
    }

    static func builtApp(in derivedData: URL, configuration: String, simulator: Bool = false) -> URL? {
        let products = derivedData.appendingPathComponent("Build/Products/\(configuration)-\(simulator ? "iphonesimulator" : "iphoneos")")
        return ((try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)) ?? [])
            .first { $0.pathExtension == "app" }
    }

    static func bundleID(of app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Info.plist"))?["CFBundleIdentifier"] as? String
    }

    /// xcode-select may point at the Command Line Tools, which have no xcodebuild/devicectl.
    static var environment: [String: String] {
        let xcode = "/Applications/Xcode.app/Contents/Developer"
        return FileManager.default.fileExists(atPath: xcode) ? ["DEVELOPER_DIR": xcode] : [:]
    }
}

extension AppState {
    /// Physical iPhones/iPads, simulators and Android devices, for the Run on… menus.
    func refreshDevices() async {
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun"), env = IPhone.environment
        let adb = Local.adbPath(editorLocations: editors.map(\.location)).map(URL.init(fileURLWithPath:))
        let list = FileManager.default.temporaryDirectory.appendingPathComponent("devicectl-\(UUID().uuidString).json")
        async let physical = Shell.run(xcrun, ["devicectl", "list", "devices", "--json-output", list.path, "--quiet"], environment: env)
        async let sims = Shell.run(xcrun, ["simctl", "list", "devices", "available", "-j"], environment: env)
        _ = await physical
        iosDevices = IPhone.devices(fromDevicectlJSON: (try? Data(contentsOf: list)) ?? Data())
        try? FileManager.default.removeItem(at: list)
        simulators = IPhone.simulators(fromSimctlJSON: Data(await sims.output.utf8))
        if let adb { androidDevices = Android.deviceList(fromADBOutput: await Shell.run(adb, ["devices", "-l"]).output) }
    }

    /// Signs the Unity-generated Xcode project with the project's Team ID, installs it on `device`
    /// and launches it.
    func installOnIPhone(buildFolder: URL, team: String, device: IPhone.Device) {
        runSteps("Run on \(device.name)") { item in
            guard let project = Xcode.project(in: buildFolder) else {
                throw StepError(message: "No Xcode project in \(buildFolder.path).")
            }
            let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun"), env = IPhone.environment
            item.log.append("Device: \(device.name)")

            item.log.append("Building and signing with Xcode (several minutes the first time)…")
            let derivedData = IPhone.derivedData(for: buildFolder)
            let configuration = IPhone.runConfiguration(buildFolder: buildFolder)
            item.log.append("Configuration: \(configuration)")
            let build = await Shell.run(xcrun, ["xcodebuild"] + IPhone.xcodebuildArguments(project: project, team: team, derivedData: derivedData,
                                                                                           configuration: configuration),
                                        environment: env)
            guard build.status == 0, let app = IPhone.builtApp(in: derivedData, configuration: configuration) else {
                item.failureDetails = IPhone.errors(fromXcodebuild: build.output)
                throw StepError(message: "xcodebuild failed.")
            }

            item.log.append("Installing \(app.lastPathComponent)…")
            let install = await Shell.run(xcrun, ["devicectl", "device", "install", "app", "--device", device.udid, app.path], environment: env)
            guard install.status == 0 else {
                item.failureDetails = Array(install.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.suffix(3))
                throw StepError(message: "Install failed.")
            }

            if let bundleID = IPhone.bundleID(of: app) {
                item.log.append("Launching \(bundleID)")
                let launch = await Shell.run(xcrun, ["devicectl", "device", "process", "launch", "--device", device.udid, bundleID], environment: env)
                // Installed either way; a locked phone just means "tap the icon".
                item.log.append(launch.status == 0 ? "Launched." : "Couldn't launch it (is the iPhone unlocked?). Open it from the home screen.")
            }
            item.summary = "Installed on \(device.name)"
        }
    }
}

extension AppState {
    /// Builds a Simulator-SDK Unity build for the simulator (no signing), boots it, installs and launches.
    func runOnSimulator(buildFolder: URL, simulator: IPhone.Simulator) {
        runSteps("Run on \(simulator.name)") { item in
            guard let project = Xcode.project(in: buildFolder) else {
                throw StepError(message: "No Xcode project in \(buildFolder.path).")
            }
            let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun"), env = IPhone.environment
            let configuration = IPhone.runConfiguration(buildFolder: buildFolder)
            let derivedData = IPhone.derivedData(for: buildFolder)
            item.log.append("Simulator: \(simulator.name) (\(simulator.runtime)), configuration \(configuration)")
            item.log.append("Building for the simulator…")
            let build = await Shell.run(xcrun, ["xcodebuild"] + IPhone.xcodebuildArguments(project: project, team: nil, derivedData: derivedData,
                                                                                           configuration: configuration, simulator: simulator.udid),
                                        environment: env)
            guard build.status == 0, let app = IPhone.builtApp(in: derivedData, configuration: configuration, simulator: true) else {
                item.failureDetails = IPhone.errors(fromXcodebuild: build.output)
                let deviceOnly = build.output.contains("but linking in object file")
                throw StepError(message: deviceOnly
                    ? "A native plugin has no simulator version, so this project can't run on simulators (see below)."
                    : "xcodebuild failed. Is this a Simulator build?")
            }
            if !simulator.booted {
                item.log.append("Booting \(simulator.name)…")
                _ = await Shell.run(xcrun, ["simctl", "boot", simulator.udid], environment: env)
            }
            if let developer = env["DEVELOPER_DIR"] {
                NSWorkspace.shared.open(URL(fileURLWithPath: developer).appendingPathComponent("Applications/Simulator.app"))
            }
            item.log.append("Installing \(app.lastPathComponent)…")
            let install = await Shell.run(xcrun, ["simctl", "install", simulator.udid, app.path], environment: env)
            guard install.status == 0 else {
                item.failureDetails = Array(install.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.suffix(3))
                throw StepError(message: "Install failed.")
            }
            if let bundleID = IPhone.bundleID(of: app) {
                item.log.append("Launching \(bundleID)")
                _ = await Shell.run(xcrun, ["simctl", "launch", simulator.udid, bundleID], environment: env)
            }
            item.summary = "Running on \(simulator.name)"
        }
    }
}
