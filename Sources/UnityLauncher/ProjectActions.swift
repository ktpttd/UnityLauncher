import SwiftUI

extension AppState {
    func installEditor(_ version: String) {
        runTask("Install Unity \(version)", ["install", version, "--yes", "--accept-eula"])
    }

    func showSize(_ row: ProjectRow) async {
        guard let cli else { return }
        await perform {
            let size = try await cli.run(["projects", "size", row.project.path], as: ProjectSize.self)
            info = InfoMessage(title: "\(row.project.title) — disk usage", message: size.summary)
        }
    }

    func templates(for version: String) async -> [Template] {
        guard let cli else { return [] }
        do { return try await cli.run(["templates", "list", "--editor", version, "--type", "core"], as: [Template].self) }
        catch { errorMessage = error.localizedDescription; return [] }
    }

    func buildProfiles(project: String) async -> [BuildProfile] {
        guard let cli else { return [] }
        return (try? await cli.run(["build", project, "--list-profiles"], as: [BuildProfile].self)) ?? []
    }

    /// Company / product from ProjectSettings, falling back to Unity's defaults.
    func player(_ row: ProjectRow) -> (company: String, product: String) {
        Local.playerSettings(at: URL(fileURLWithPath: row.project.path)) ?? ("DefaultCompany", row.project.title)
    }
}

/// `unity build --list-profiles` row (Unity 6+ Build Profile asset).
struct BuildProfile: Decodable, Hashable, Identifiable {
    var id: String { path }
    let profile: String
    let path: String
}

enum ProjectSheet: Identifiable {
    case newProject, upgrade(ProjectRow), build(ProjectRow), buildReport(ProjectRow)
    var id: String {
        switch self {
        case .newProject: "new"
        case .upgrade(let r): "upgrade" + r.id
        case .build(let r): "build" + r.id
        case .buildReport(let r): "report" + r.id
        }
    }
}

struct NewProjectSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("newProjectFolder") private var folder = NSString(string: "~/UnityProjects").expandingTildeInPath
    @State private var name = "NewProject"
    @State private var version = ""
    @State private var templates: [Template] = []
    @State private var template = ""
    @State private var openAfter = true

    var body: some View {
        Form {
            TextField("Name", text: $name)
            LabeledContent("Location") {
                HStack {
                    Text(folder).truncationMode(.head).lineLimit(1)
                    Button("Choose…") { if let url = Mac.chooseFolder(message: "Parent folder for new projects") { folder = url.path } }
                }
            }
            Picker("Unity Version", selection: $version) {
                ForEach(state.editors) { Text($0.version).tag($0.version) }
            }
            Picker("Template", selection: $template) {
                if templates.isEmpty { Text("Loading…").tag("") }
                ForEach(templates) { Text($0.displayName).tag($0.name) }
            }
            Toggle("Open after creating", isOn: $openAfter)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .task(id: version) {
            if version.isEmpty { version = state.editors.first(where: \.isDefault)?.version ?? state.editors.first?.version ?? "" }
            guard !version.isEmpty else { return }
            templates = await state.templates(for: version)
            template = templates.first { $0.name == "com.unity.template.urp-blank" }?.name ?? templates.first?.name ?? ""
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
                    state.runTask("Create \(name)", ["projects", "new", name, "--path", folder, "--editor-version", version, "--template", template]
                                  + (openAfter ? ["--open"] : []))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || version.isEmpty || template.isEmpty)
            }
        }
    }
}

struct UpgradeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let row: ProjectRow
    @State private var target = ""

    var body: some View {
        Form {
            LabeledContent("Project", value: row.project.title)
            LabeledContent("Current version", value: row.project.version)
            Picker("Upgrade to", selection: $target) {
                ForEach(state.editors.filter { $0.version != row.project.version }) { Text($0.version).tag($0.version) }
            }
            Text("Back up or commit the project first. Unity opens it with the new version and re-imports assets.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear {
            target = UnityVersion.suggestUpgrade(from: row.project.version, installed: state.editors.map(\.version))
                ?? state.editors.first { $0.version != row.project.version }?.version ?? ""
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Upgrade") {
                    state.runTask("Upgrade \(row.project.title) → \(target)", ["projects", "upgrade", row.project.path, "--to", target, "--yes"])
                    dismiss()
                }
                .disabled(target.isEmpty)
            }
        }
    }
}

struct BuildSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let row: ProjectRow
    @State private var target = BuildTarget.macOS
    @State private var profiles: [BuildProfile] = []
    @State private var profile = ""
    @State private var output = ""
    @State private var allowDirty = false
    @State private var creatingProfile = false

    private var isUnity6: Bool { (UnityVersion(row.project.version)?.major ?? 0) >= 6000 }
    /// Batch builds can't open a project the Editor already has open.
    private var isOpen: Bool { state.projects.first { $0.id == row.id }?.pid != nil }

    var body: some View {
        Form {
            Picker("Target", selection: $target) {
                ForEach(BuildTarget.allCases) { Text($0.label).tag($0) }
            }
            if target.needsProfile {
                if isUnity6 {
                    Picker("Build Profile", selection: $profile) {
                        if profiles.isEmpty { Text("None in project").tag("") }
                        ForEach(profiles) { Text($0.profile).tag($0.path) }
                    }
                    Button(creatingProfile ? "Creating \(target.label) profile…" : "Create \(target.label) Profile") {
                        createProfile()
                    }
                    .disabled(creatingProfile || isOpen)
                } else {
                    Text("\(target.label) builds need a Unity 6 Build Profile. This project uses \(row.project.version).")
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Output", text: $output)
            Toggle("Allow uncommitted changes", isOn: $allowDirty)
            if isOpen {
                Label("Unity has this project open. Close it first: a batch build can't open the same project.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onChange(of: target, initial: true) {
            output = target.defaultOutput(project: row.project.path, product: state.player(row).product)
        }
        .task { await loadProfiles() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Build") {
                    let args = BuildTarget.arguments(project: row.project.path, target: target,
                                                     profile: target.needsProfile ? profile : nil,
                                                     output: output, allowDirty: allowDirty)
                    state.runTask("Build \(row.project.title) (\(target.label))", args)
                    dismiss()
                }
                .disabled(output.isEmpty || isOpen || (target.needsProfile && profile.isEmpty))
            }
        }
    }

    private func loadProfiles() async {
        guard isUnity6 else { return }
        profiles = await state.buildProfiles(project: row.project.path)
        if !profiles.contains(where: { $0.path == profile }) {
            profile = profiles.first { $0.profile.localizedCaseInsensitiveContains(target.label) }?.path ?? profiles.first?.path ?? ""
        }
    }

    private func createProfile() {
        creatingProfile = true
        let item = state.runTask("Create \(target.label) profile: \(row.project.title)",
                                 ["build", row.project.path, "--create-profile", target.rawValue], refreshAfter: false)
        Task {
            await item.task?.value
            creatingProfile = false
            await loadProfiles()
        }
    }
}
