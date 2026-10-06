import SwiftUI

struct ProjectsView: View {
    @Environment(AppState.self) private var state
    @State private var selection: ProjectRow.ID?
    @State private var editingArgs: ProjectRow?
    @State private var argsText = ""
    @State private var confirmKill: ProjectRow?
    @State private var confirmRemove: ProjectRow?
    @State private var confirmClean: ProjectRow?
    @State private var sheet: ProjectSheet?

    private var selected: ProjectRow? { state.projects.first { $0.id == selection } }

    var body: some View {
        @Bindable var state = state
        Table(state.filteredProjects, selection: $selection) {
            TableColumn("Name") { row in
                HStack(spacing: 4) {
                    if row.pid != nil { Image(systemName: "circle.fill").foregroundStyle(.green).font(.system(size: 7)).help("Running") }
                    if row.project.isFavorite == true { Image(systemName: "pin.fill").foregroundStyle(.orange).font(.caption) }
                    Text(row.project.title)
                }
                .foregroundStyle(row.exists ? .primary : .secondary)
                .help(row.exists ? row.project.path : "Folder not found")
            }
            TableColumn("Version") { row in
                Text(row.project.version)
                    .foregroundStyle(state.installedVersions.contains(row.project.version) ? Color.primary : Color.red)
                    .help(state.installedVersions.contains(row.project.version) ? "" : "Editor not installed")
            }
            .width(min: 80, ideal: 95)
            TableColumn("Branch") { row in Text(row.branch ?? "") }
            .width(min: 60, ideal: 100)
            TableColumn("Platform") { row in Text(row.project.buildTarget ?? "") }
            .width(min: 60, ideal: 90)
            TableColumn("SRP") { row in Text(row.project.renderPipeline ?? "") }
            .width(min: 40, ideal: 70)
            TableColumn("Modified") { row in
                Text(row.project.modified?.formatted(.relative(presentation: .named)) ?? "")
            }
            .width(min: 70, ideal: 100)
            TableColumn("Path") { row in Text(row.project.path).foregroundStyle(.secondary).truncationMode(.head) }
        }
        .contextMenu(forSelectionType: ProjectRow.ID.self) { ids in
            if let row = state.projects.first(where: { ids.contains($0.id) }) { menu(for: row) }
        } primaryAction: { ids in
            if let row = state.projects.first(where: { ids.contains($0.id) }), row.exists {
                Task { await state.open(row) }
            }
        }
        .searchable(text: $state.search, placement: .toolbar, prompt: "Search name or path")
        .dropDestination(for: URL.self) { urls, _ in
            Task { for url in urls { await state.cliAction(["projects", "add", url.path]) } }
            return true
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Open", systemImage: "play.fill") { if let s = selected { Task { await state.open(s) } } }
                    .disabled(selected?.exists != true)
                    .keyboardShortcut(.return, modifiers: [])
                Button("Kill Unity", systemImage: "xmark.octagon") { confirmKill = selected }
                    .disabled(selected?.pid == nil)
                    .keyboardShortcut("q", modifiers: .option)
                Button("New Project", systemImage: "doc.badge.plus") { sheet = .newProject }
                    .keyboardShortcut("n")
                    .disabled(state.editors.isEmpty)
                Button("Add Project", systemImage: "plus") {
                    if let url = Mac.chooseFolder(message: "Choose a Unity project folder") {
                        Task { await state.cliAction(["projects", "add", url.path]) }
                    }
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newProject: NewProjectSheet()
            case .upgrade(let row): UpgradeSheet(row: row)
            case .build(let row): BuildSheet(row: row)
            }
        }
        .confirmationDialog("Delete Library, Temp and Logs of \(confirmClean?.project.title ?? "")?", isPresented: .init(get: { confirmClean != nil }, set: { if !$0 { confirmClean = nil } })) {
            Button("Clean", role: .destructive) {
                if let row = confirmClean { state.runTask("Clean \(row.project.title)", ["projects", "clean", row.project.path, "--yes"]) }
            }
        } message: {
            Text("Unity regenerates them on next open (slow first import). The CLI refuses while the project is open.")
        }
        .alert("Arguments for \(editingArgs?.project.title ?? "")", isPresented: .init(get: { editingArgs != nil }, set: { if !$0 { editingArgs = nil } })) {
            TextField("-logFile out.log", text: $argsText)
            Button("Save") { if let row = editingArgs { ProjectPrefs.setArgs(argsText, for: row.project.path) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Extra Unity command-line arguments used every time this project opens.")
        }
        .confirmationDialog("Kill Unity for \(confirmKill?.project.title ?? "")?", isPresented: .init(get: { confirmKill != nil }, set: { if !$0 { confirmKill = nil } })) {
            Button("Kill Process", role: .destructive) { if let row = confirmKill { Task { await state.kill(row) } } }
        } message: {
            Text("Unsaved changes in the Editor will be lost.")
        }
        .confirmationDialog("Remove \(confirmRemove?.project.title ?? "") from the list?", isPresented: .init(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button("Remove", role: .destructive) { if let row = confirmRemove { Task { await state.cliAction(["projects", "remove", row.project.path]) } } }
        } message: {
            Text("Files on disk are not touched.")
        }
    }

    private func runTests(_ row: ProjectRow, mode: String) {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(row.project.title)-\(mode)-results.xml").path
        state.runTask("\(mode) tests: \(row.project.title)", ["test", row.project.path, "--mode", mode, "--output", out], refreshAfter: false)
    }

    @ViewBuilder
    private func menu(for row: ProjectRow) -> some View {
        let path = row.project.path
        if row.exists {
            Button("Open") { Task { await state.open(row) } }
            Menu("Open With") {
                ForEach(state.editors) { e in
                    Button(e.version) { Task { await state.open(row, version: e.version) } }
                }
            }
            Button("Arguments…") { argsText = ProjectPrefs.args(for: path); editingArgs = row }
            Divider()
            Button("Reveal in Finder") { Mac.reveal(path) }
            Button("Open in Terminal") { Mac.openInTerminal(path) }
            Button("Edit Packages (manifest.json)") { Mac.reveal(path + "/Packages/manifest.json") }
            Divider()
            Button("Upgrade…") { sheet = .upgrade(row) }
            Button("Build…") { sheet = .build(row) }
            Button("Run WebGL Build…") {
                if let url = Mac.chooseFolder(message: "Choose the WebGL build folder (contains index.html)") {
                    state.runServer("WebGL: \(row.project.title)", ["build", "run", path, "--path", url.path])
                }
            }
            Menu("Run Tests") {
                Button("EditMode") { runTests(row, mode: "EditMode") }
                Button("PlayMode") { runTests(row, mode: "PlayMode") }
            }
            Menu("Logs & Data") {
                Button("Editor.log") { Mac.reveal(Local.Folder.editorLogs.url.appendingPathComponent("Editor.log").path) }
                Button("Player.log") { let p = state.player(row); Mac.open(Local.playerLogURL(company: p.company, product: p.product).deletingLastPathComponent()) }
                Button("Persistent Data Path") { let p = state.player(row); Mac.open(Local.persistentDataURL(company: p.company, product: p.product)) }
                Button("Project Logs Folder") { Mac.open(URL(fileURLWithPath: path + "/Logs")) }
            }
            Menu("Maintenance") {
                Button("Disk Usage") { Task { await state.showSize(row) } }
                Button("Verify Project") { state.runTask("Verify \(row.project.title)", ["projects", "verify", path], refreshAfter: false) }
                Button("Clean Library…") { confirmClean = row }
            }
        }
        Button("Copy Path") { Mac.copy(path) }
        Button("Copy Version") { Mac.copy(row.project.version) }
        Divider()
        if row.project.isFavorite == true {
            Button("Unpin") { Task { await state.cliAction(["projects", "unpin", path]) } }
        } else {
            Button("Pin to Top") { Task { await state.cliAction(["projects", "pin", path]) } }
        }
        if row.pid != nil {
            Button("Kill Unity Process") { confirmKill = row }
        }
        Button("Remove from List…") { confirmRemove = row }
    }
}
