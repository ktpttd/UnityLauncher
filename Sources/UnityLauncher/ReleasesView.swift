import SwiftUI

struct ReleasesView: View {
    @Environment(AppState.self) private var state
    @State private var selection: Release.ID?
    @State private var confirmInstall: Release?

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            HStack {
                Picker("Stream", selection: $state.releaseStream) {
                    ForEach(ReleaseStream.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                TextField("Filter versions", text: $state.releaseSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Spacer()
            }
            .padding(8)
            Table(state.filteredReleases, selection: $selection) {
                TableColumn("Version", value: \.version).width(min: 110, ideal: 130)
                TableColumn("Stream") { r in Text(r.lts ? "LTS" : r.stream.capitalized) }.width(min: 60, ideal: 80)
                TableColumn("Arch", value: \.architecture).width(min: 50, ideal: 60)
                TableColumn("Installed") { r in
                    if r.installed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                .width(min: 60, ideal: 70)
            }
            .contextMenu(forSelectionType: Release.ID.self) { ids in
                if let r = state.releases.first(where: { ids.contains($0.id) }) {
                    Button("Install…") { confirmInstall = r }.disabled(r.installed)
                    if let url = UnityVersion.releaseNotesURL(r.version) {
                        Button("Release Notes") { NSWorkspace.shared.open(url) }
                    }
                    Button("Copy Version") { Mac.copy(r.version) }
                }
            } primaryAction: { ids in
                if let r = state.releases.first(where: { ids.contains($0.id) }),
                   let url = UnityVersion.releaseNotesURL(r.version) { NSWorkspace.shared.open(url) }
            }
        }
        .overlay { if state.releasesLoading { ProgressView("Loading releases…").padding().background(.regularMaterial, in: .rect(cornerRadius: 8)) } }
        .task(id: state.releaseStream) { await state.loadReleases() }
        .confirmationDialog("Install Unity \(confirmInstall?.version ?? "")?", isPresented: .init(get: { confirmInstall != nil }, set: { if !$0 { confirmInstall = nil } })) {
            Button("Install") { if let r = confirmInstall { state.installEditor(r.version) } }
        } message: {
            Text("Downloads several GB and accepts the Unity Editor EULA. Add platform modules later from the Editors tab.")
        }
    }
}
