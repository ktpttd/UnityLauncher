import SwiftUI

struct TasksView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tasks").font(.headline)
                Spacer()
                Button("Clear Finished") { state.tasks.removeAll { $0.state != .running } }
                    .disabled(!state.tasks.contains { $0.state != .running })
            }
            .padding(8)
            Divider()
            List(state.tasks) { TaskRow(item: $0) }
                .overlay {
                    if state.tasks.isEmpty { ContentUnavailableView("No Tasks", systemImage: "checklist") }
                }
        }
    }
}

private struct TaskRow: View {
    @Environment(AppState.self) private var state
    let item: TaskItem
    @State private var expanded = false
    @State private var askingTeam = false
    @State private var teamText = ""
    /// iPhone waiting for a Team ID before installing.
    @State private var pendingDevice: IPhone.Device?

    /// Last device used for this project (per kind), else the first one available.
    private func preferred<T: Identifiable>(_ devices: [T], kind: String) -> T? where T.ID == String {
        let last = item.project.flatMap { ProjectPrefs.lastDevice(for: $0, kind: kind) }
        return devices.first { $0.id == last } ?? devices.first
    }

    /// Physical iPhone/iPad: signing needs the project's Team ID, asked for the first time.
    private func run(on device: IPhone.Device, _ buildFolder: URL, changeTeam: Bool = false) {
        guard let project = item.project else { return }
        ProjectPrefs.setLastDevice(device.udid, for: project, kind: "ios")
        let team = ProjectPrefs.teamID(for: project)
        if changeTeam || !IPhone.isValidTeamID(team) {
            teamText = team
            pendingDevice = device
            askingTeam = true
        } else {
            state.installOnIPhone(buildFolder: buildFolder, team: team, device: device)
        }
    }

    private func run(on simulator: IPhone.Simulator, _ buildFolder: URL) {
        if let project = item.project { ProjectPrefs.setLastDevice(simulator.udid, for: project, kind: "simulator") }
        state.runOnSimulator(buildFolder: buildFolder, simulator: simulator)
    }

    private func install(_ apk: URL, on device: Android.Device) {
        if let project = item.project { ProjectPrefs.setLastDevice(device.serial, for: project, kind: "android") }
        state.installOnDevice(apk, device: device)
    }

    private func useTeam(_ team: String, _ buildFolder: URL) {
        guard let project = item.project else { return }
        ProjectPrefs.setTeamID(team, for: project)
        if let device = pendingDevice { state.installOnIPhone(buildFolder: buildFolder, team: team, device: device) }
    }

    private var refreshButton: some View {
        Button("Refresh Devices") { Task { await state.refreshDevices() } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                switch item.state {
                case .running: Image(systemName: "hourglass").foregroundStyle(.blue)
                case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                Text(item.title).bold().lineLimit(1)
                Spacer()
                if item.state == .running { Button("Stop") { item.stop() }.controlSize(.small) }
            }
            Group {
                if item.state == .running {
                    Text(item.startedAt, style: .timer).monospacedDigit()
                } else if let end = item.finishedAt {
                    let took = formatDuration(end.timeIntervalSince(item.startedAt))
                    Text(item.state == .succeeded ? "Done in \(took)" : "Ended after \(took)")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let summary = item.summary {
                Text(summary).font(.callout.weight(.semibold)).textSelection(.enabled)
                // Stacked and right-aligned: the inspector is too narrow for a row of buttons.
                VStack(alignment: .trailing, spacing: 4) {
                    if let output = item.output {
                        if let row = state.projects.first(where: { $0.project.path == item.project }) {
                            Button("Build Report") { state.buildReportFor = row }.controlSize(.small)
                        }
                        Button("Open Path") { Mac.open(buildOutputFolder(output)) }.controlSize(.small)
                        if output.pathExtension == "apk" {
                            Menu("Run on Device") {
                                ForEach(state.androidDevices) { d in
                                    Button("\(d.model) (\(d.serial))") { install(output, on: d) }
                                }
                                if state.androidDevices.isEmpty { Text("No Android device connected") }
                                Divider()
                                refreshButton
                            } primaryAction: {
                                if let d = preferred(state.androidDevices, kind: "android") { install(output, on: d) }
                                else { state.installOnDevice(output) } // explains that nothing is connected
                            }
                            .controlSize(.small).fixedSize()
                        } else if output.pathExtension == "aab" {
                            Button("Run on Device") {}.controlSize(.small).disabled(true)
                                .help("App Bundles (.aab) can't be installed directly. Build an APK profile such as Android_DEV to test on a device.")
                        }
                        if let xcode = Xcode.project(in: output) {
                            Button("Open in Xcode") { NSWorkspace.shared.open(xcode) }.controlSize(.small)
                            if item.simulatorSDK {
                                Menu("Run on Simulator") {
                                    ForEach(state.simulators) { sim in
                                        Button("\(sim.name) — \(sim.runtime)\(sim.booted ? " (running)" : "")") { run(on: sim, output) }
                                    }
                                    if state.simulators.isEmpty { Text("No simulators available") }
                                    Divider()
                                    refreshButton
                                } primaryAction: {
                                    if let sim = preferred(state.simulators, kind: "simulator") { run(on: sim, output) }
                                }
                                .controlSize(.small).fixedSize()
                            } else {
                                Menu("Run on Device") {
                                    ForEach(state.iosDevices) { d in
                                        Button(d.name) { run(on: d, output) }
                                    }
                                    if state.iosDevices.isEmpty { Text("No iPhone or iPad connected") }
                                    Divider()
                                    Button("Change Team ID…") {
                                        teamText = item.project.map(ProjectPrefs.teamID(for:)) ?? ""
                                        pendingDevice = nil
                                        askingTeam = true
                                    }
                                    refreshButton
                                } primaryAction: {
                                    if let d = preferred(state.iosDevices, kind: "ios") { run(on: d, output) }
                                    else { state.errorMessage = "No iPhone or iPad connected. Plug one in, unlock it and tap Trust." }
                                }
                                .controlSize(.small).fixedSize()
                                .help("Sign with your Apple team, install and launch, without opening Xcode. Simulators need a Simulator build (Build sheet).")
                                .alert("Apple Developer Team ID", isPresented: $askingTeam) {
                                    // Teams signed into Xcode, one click each; or type an ID.
                                    ForEach(IPhone.xcodeTeams) { team in
                                        Button(team.name) { useTeam(team.id, output) }
                                    }
                                    TextField("ABCDE12345", text: $teamText)
                                    Button(pendingDevice == nil ? "Save" : "Install") {
                                        let team = teamText.trimmingCharacters(in: .whitespaces).uppercased()
                                        guard IPhone.isValidTeamID(team) else {
                                            state.errorMessage = "A Team ID is 10 letters and digits, like ABCDE12345."
                                            return
                                        }
                                        useTeam(team, output)
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("Pick a team signed into Xcode, or type its ID (developer.apple.com → Membership). It's remembered for this project.")
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .task(id: item.finishedAt) { if item.output != nil { await state.refreshDevices() } }
            }
            if item.state == .running {
                if let pct = item.pct { ProgressView(value: min(pct, 100), total: 100) }
                else { ProgressView().progressViewStyle(.linear) }
            }
            if case .failed(let message) = item.state {
                Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                ForEach(item.failureDetails, id: \.self) { line in
                    Text(line).font(.system(.caption, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            DisclosureGroup("Log (\(item.log.count))", isExpanded: $expanded) {
                ScrollView {
                    Text(item.log.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
            .font(.caption)
            if !expanded, let last = item.log.last {
                Text(last).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
