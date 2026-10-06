import SwiftUI

struct EditorsView: View {
    @Environment(AppState.self) private var state
    @State private var selection: EditorInstall.ID?
    @State private var modulesFor: EditorInstall?
    @State private var confirmUninstall: EditorInstall?

    var body: some View {
        Table(state.editors, selection: $selection) {
            TableColumn("Version") { e in
                HStack(spacing: 4) {
                    Text(e.version)
                    if e.isDefault { Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption).help("Default editor") }
                }
            }
            .width(min: 100, ideal: 120)
            TableColumn("Arch", value: \.architecture).width(min: 50, ideal: 60)
            TableColumn("Modules") { e in Text(e.modules).foregroundStyle(.secondary) }
            TableColumn("Location") { e in Text(e.location).foregroundStyle(.secondary).truncationMode(.head) }
        }
        .contextMenu(forSelectionType: EditorInstall.ID.self) { ids in
            if let e = state.editors.first(where: { ids.contains($0.id) }) { menu(for: e) }
        } primaryAction: { ids in
            if let e = state.editors.first(where: { ids.contains($0.id) }) { NSWorkspace.shared.open(URL(fileURLWithPath: e.location)) }
        }
        .sheet(item: $modulesFor) { ModulesSheet(editor: $0) }
        .confirmationDialog("Uninstall Unity \(confirmUninstall?.version ?? "")?", isPresented: .init(get: { confirmUninstall != nil }, set: { if !$0 { confirmUninstall = nil } })) {
            Button("Uninstall", role: .destructive) {
                if let e = confirmUninstall {
                    state.runTask("Uninstall \(e.version)", ["uninstall", e.version, "--architecture", e.architecture, "--yes"])
                }
            }
        } message: {
            Text("Deletes the editor folder. Projects are not affected.")
        }
    }

    @ViewBuilder
    private func menu(for e: EditorInstall) -> some View {
        Button("Run Unity") { NSWorkspace.shared.open(URL(fileURLWithPath: e.location)) }
        Button("Reveal in Finder") { Mac.reveal(e.location) }
        Button("Copy Path") { Mac.copy(e.location) }
        Button("Copy Version") { Mac.copy(e.version) }
        if let url = UnityVersion.releaseNotesURL(e.version) {
            Button("Release Notes") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button("Set as Default") { Task { await state.cliAction(["editors", "default", e.version]) } }
            .disabled(e.isDefault)
        Button("Add Modules…") { modulesFor = e }
        Button("Upgrade to Latest Patch") {
            state.runTask("Upgrade editor \(e.version)", ["editors", "upgrade", e.version, "--yes", "--accept-eula"])
        }
        Divider()
        Button("Uninstall…") { confirmUninstall = e }
    }
}

struct ModulesSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let editor: EditorInstall
    @State private var modules: [ModuleInfo]?
    @State private var picked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Modules for Unity \(editor.version)").font(.headline).padding()
            if let modules {
                List(modules) { m in
                    Toggle(isOn: .init(get: { m.isInstalled || picked.contains(m.id) },
                                       set: { if $0 { picked.insert(m.id) } else { picked.remove(m.id) } })) {
                        VStack(alignment: .leading) {
                            Text(m.name)
                            Text([m.category, m.download].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(m.isInstalled)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Installing accepts the module EULAs.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Install \(picked.count)") {
                    state.runTask("Modules for \(editor.version)",
                                  AppState.moduleAddArguments(version: editor.version, modules: picked.sorted()))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(picked.isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 480)
        .task { modules = await state.modules(for: editor.version) }
    }
}
