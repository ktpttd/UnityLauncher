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

    /// Installs on an iPhone, asking for the project's Apple Team ID the first time.
    private func installOnIPhone(_ buildFolder: URL, changeTeam: Bool = false) {
        guard let project = item.project else { return }
        let team = ProjectPrefs.teamID(for: project)
        if changeTeam || !IPhone.isValidTeamID(team) {
            teamText = team
            askingTeam = true
        } else {
            state.installOnIPhone(buildFolder: buildFolder, team: team)
        }
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
                            Button("Install on Device") { state.installOnDevice(output) }.controlSize(.small)
                        } else if output.pathExtension == "aab" {
                            Button("Install on Device") {}.controlSize(.small).disabled(true)
                                .help("App Bundles (.aab) can't be installed directly. Build an APK profile such as Android_DEV to test on a device.")
                        }
                        if let xcode = Xcode.project(in: output) {
                            Button("Open in Xcode") { NSWorkspace.shared.open(xcode) }.controlSize(.small)
                            Menu("Install on iPhone") {
                                Button("Change Team ID…") { installOnIPhone(output, changeTeam: true) }
                            } primaryAction: {
                                installOnIPhone(output)
                            }
                            .controlSize(.small)
                            .fixedSize()
                            .alert("Apple Developer Team ID", isPresented: $askingTeam) {
                                // Teams signed into Xcode, one click each; or type an ID.
                                ForEach(IPhone.xcodeTeams) { team in
                                    Button(team.name) {
                                        guard let project = item.project else { return }
                                        ProjectPrefs.setTeamID(team.id, for: project)
                                        state.installOnIPhone(buildFolder: output, team: team.id)
                                    }
                                }
                                TextField("ABCDE12345", text: $teamText)
                                Button("Install") {
                                    let team = teamText.trimmingCharacters(in: .whitespaces).uppercased()
                                    guard IPhone.isValidTeamID(team), let project = item.project else {
                                        state.errorMessage = "A Team ID is 10 letters and digits, like ABCDE12345."
                                        return
                                    }
                                    ProjectPrefs.setTeamID(team, for: project)
                                    state.installOnIPhone(buildFolder: output, team: team)
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Pick a team signed into Xcode, or type its ID (developer.apple.com → Membership). It's remembered for this project.")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
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
