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
        let url = URL(fileURLWithPath: project)
        return await Task.detached { Local.buildProfiles(in: url) }.value
    }

    /// Company / product from ProjectSettings, falling back to Unity's defaults.
    func player(_ row: ProjectRow) -> (company: String, product: String) {
        Local.playerSettings(at: URL(fileURLWithPath: row.project.path)) ?? ("DefaultCompany", row.project.title)
    }
}

/// A Unity 6+ Build Profile asset. `path` is project-relative, as `unity build --profile` takes it.
struct BuildProfile: Hashable, Identifiable {
    var id: String { path }
    let profile: String
    let path: String
    /// nil for platforms the Build sheet doesn't list (consoles, XR…).
    let target: BuildTarget?
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
    @State private var target: BuildTarget
    @State private var profiles: [BuildProfile] = []
    @State private var profile = ""
    @State private var output = ""
    @State private var allowDirty = false
    @State private var creatingProfile = false
    @State private var signing: AndroidSigning?
    // Kept only while the sheet is open; never written anywhere.
    @State private var keystorePassword = ""
    @State private var aliasPassword = ""
    /// Version fields as read from the profile (or Player Settings); edits are saved before building.
    @State private var loadedVersion: BuildVersion?
    @State private var version = BuildVersion(version: "", androidCode: "", iosBuild: "")

    private var versionFile: URL {
        BuildVersion.file(project: URL(fileURLWithPath: row.project.path), profile: profile.isEmpty ? nil : profile)
    }

    private var needsPassword: Bool { target == .android && signing?.custom == true }

    init(row: ProjectRow) {
        self.row = row
        // Start on the project's active platform (from the Hub/CLI), e.g. iOS for a mobile game.
        _target = State(initialValue: row.project.buildTarget.flatMap(BuildTarget.init(rawValue:)) ?? .macOS)
    }

    private var isUnity6: Bool { (UnityVersion(row.project.version)?.major ?? 0) >= 6000 }
    /// Batch builds can't open a project the Editor already has open.
    private var isOpen: Bool { state.projects.first { $0.id == row.id }?.pid != nil }

    var body: some View {
        Form {
            Picker("Target", selection: $target) {
                ForEach(BuildTarget.allCases) { Text($0.label).tag($0) }
            }
            if isUnity6 {
                Picker("Build Profile", selection: $profile) {
                    Text(target.needsProfile ? "Choose a profile" : "None (plain \(target.label) build)").tag("")
                    ForEach(profiles) { p in
                        Text("\(p.profile) · \(p.target?.label ?? "Other")").tag(p.path)
                    }
                }
                if target.needsProfile, !profiles.contains(where: { $0.target == target }) {
                    Button(creatingProfile ? "Creating \(target.label) profile…" : "Create \(target.label) Profile") {
                        createProfile()
                    }
                    .disabled(creatingProfile || isOpen)
                }
            } else if target.needsProfile {
                Text("\(target.label) builds need a Unity 6 Build Profile. This project uses \(row.project.version).")
                    .foregroundStyle(.secondary)
            }
            if loadedVersion != nil {
                Section("Version") {
                    TextField("Version", text: $version.version)
                    if target == .android {
                        HStack {
                            TextField("Version code", text: $version.androidCode)
                            Button("+1") { version.androidCode = BuildVersion.bump(version.androidCode) }
                        }
                    }
                    if target == .iOS {
                        HStack {
                            TextField("Build", text: $version.iosBuild)
                            Button("+1") { version.iosBuild = BuildVersion.bump(version.iosBuild) }
                        }
                    }
                    if let problem = version.problem {
                        Text(problem).font(.caption).foregroundStyle(.red)
                    } else if version != loadedVersion {
                        Text("Saved to \(versionFile.lastPathComponent) when you press Build.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            TextField("Output", text: $output)
            Toggle("Allow uncommitted changes", isOn: $allowDirty)
            if needsPassword, let s = signing {
                LabeledContent("Keystore") {
                    Text(s.keystore.path.replacingOccurrences(of: row.project.path + "/", with: "") + " · alias \(s.alias)")
                        .foregroundStyle(FileManager.default.fileExists(atPath: s.keystore.path) ? Color.secondary : Color.red)
                        .lineLimit(1).truncationMode(.middle)
                }
                SecureField("Keystore password", text: $keystorePassword)
                SecureField("Alias password (if different)", text: $aliasPassword)
                Text("Signed builds run through \(BuildScript.relativePath), which the launcher adds to the project (commit it; it holds no secrets). Passwords reach it as environment variables for this build only and are never saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
            // Keep the profile only if it builds this target.
            if let current = profiles.first(where: { $0.path == profile }), current.target != target {
                profile = profiles.first { $0.target == target }?.path ?? ""
            }
        }
        .onChange(of: profile) {
            // A profile decides its platform.
            if let t = profiles.first(where: { $0.path == profile })?.target, t != target { target = t }
        }
        .task { await loadProfiles() }
        .task(id: profile) {
            let file = versionFile
            loadedVersion = await Task.detached { (try? String(contentsOf: file, encoding: .utf8)).flatMap(BuildVersion.read) }.value
            if let loadedVersion { version = loadedVersion }
        }
        .task(id: "\(target.rawValue)|\(profile)") {
            let project = URL(fileURLWithPath: row.project.path), chosen = profile.isEmpty ? nil : profile
            signing = target == .android ? await Task.detached { Local.androidSigning(project: project, profile: chosen) }.value : nil
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Build") {
                    if let loadedVersion, version != loadedVersion {
                        do {
                            let text = try String(contentsOf: versionFile, encoding: .utf8)
                            try version.write(into: text).write(to: versionFile, atomically: true, encoding: .utf8)
                        } catch {
                            state.errorMessage = "Couldn't save the version to \(versionFile.lastPathComponent): \(error.localizedDescription)"
                            return
                        }
                    }
                    let what = profiles.first { $0.path == profile }?.profile ?? target.label
                    if needsPassword {
                        // `unity build --profile` can't take keystore passwords; our build method can.
                        let project = URL(fileURLWithPath: row.project.path)
                        if BuildScript.status(project: project) != .current {
                            do { try BuildScript.install(project: project) } catch {
                                state.errorMessage = "Couldn't add \(BuildScript.relativePath): \(error.localizedDescription)"
                                return
                            }
                        }
                        state.runTask("Build \(row.project.title) (\(what), signed)",
                                      BuildScript.arguments(project: row.project.path, target: target, output: output, allowDirty: allowDirty),
                                      environment: BuildScript.environment(profile: profile, keystorePassword: keystorePassword, aliasPassword: aliasPassword))
                    } else {
                        state.runTask("Build \(row.project.title) (\(what))",
                                      BuildTarget.arguments(project: row.project.path, target: target, profile: profile.isEmpty ? nil : profile,
                                                            output: output, allowDirty: allowDirty))
                    }
                    dismiss()
                }
                .disabled(output.isEmpty || isOpen || (target.needsProfile && profile.isEmpty) || (needsPassword && (keystorePassword.isEmpty || profile.isEmpty))
                           || (loadedVersion != nil && version.problem != nil))
            }
        }
    }

    private func loadProfiles() async {
        guard isUnity6 else { return }
        profiles = await state.buildProfiles(project: row.project.path)
        if target.needsProfile, !profiles.contains(where: { $0.path == profile }) {
            profile = profiles.first { $0.target == target }?.path ?? ""
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
