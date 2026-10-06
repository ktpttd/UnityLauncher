import SwiftUI

@main
struct UnityLauncherApp: App {
    @State private var state = AppState()

    var body: some Scene {
        Window("Unity Launcher", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 820, minHeight: 420)
                .task { await state.refresh() }
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    @AppStorage("selectedTab") private var tab = "projects"

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            if state.cli == nil { CLIMissingBanner() }
            TabView(selection: $tab) {
                ProjectsView().tabItem { Text("Projects") }.tag("projects")
                EditorsView().tabItem { Text("Editors") }.tag("editors")
                ReleasesView().tabItem { Text("Releases") }.tag("releases")
            }
        }
        .inspector(isPresented: $state.showTasks) {
            TasksView().inspectorColumnWidth(min: 260, ideal: 320)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await state.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(state.isLoading)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Tasks", systemImage: state.tasks.contains { $0.state == .running } ? "list.bullet.circle.fill" : "list.bullet.circle") {
                    state.showTasks.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
        .alert(state.info?.title ?? "", isPresented: .init(get: { state.info != nil }, set: { if !$0 { state.info = nil } })) {
            Button("OK") {}
        } message: {
            Text(state.info?.message ?? "")
        }
        .alert("Error", isPresented: .init(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(state.errorMessage ?? "")
        }
        .alert("Unity \(state.missingEditorFor?.project.version ?? "") is not installed",
               isPresented: .init(get: { state.missingEditorFor != nil }, set: { if !$0 { state.missingEditorFor = nil } })) {
            if let row = state.missingEditorFor {
                Button("Install \(row.project.version)") { state.installEditor(row.project.version) }
                ForEach(state.editors.prefix(4)) { e in
                    Button("Open with \(e.version)") { Task { await state.open(row, version: e.version) } }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Install it (accepts the Unity Editor EULA) or open with another installed version.")
        }
    }
}

struct CLIMissingBanner: View {
    static let installCommand = "curl -fsSL https://public-cdn.cloud.unity3d.com/hub/prod/cli/install.sh | UNITY_CLI_CHANNEL=beta bash"

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text("Unity CLI not found").bold()
                Text("Install it in Terminal, or set its path in Settings.").font(.caption)
            }
            Spacer()
            Button("Copy Install Command") { Mac.copy(Self.installCommand) }
        }
        .padding(10)
        .background(.yellow.opacity(0.12))
    }
}
