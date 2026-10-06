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

    var body: some View {
        VStack(spacing: 0) {
            if state.cli == nil { CLIMissingBanner() }
            TabView {
                ProjectsView().tabItem { Text("Projects") }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await state.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(state.isLoading)
            }
        }
        .alert("Error", isPresented: .init(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(state.errorMessage ?? "")
        }
        .alert("Unity \(state.missingEditorFor?.project.version ?? "") is not installed",
               isPresented: .init(get: { state.missingEditorFor != nil }, set: { if !$0 { state.missingEditorFor = nil } })) {
            if let row = state.missingEditorFor {
                ForEach(state.editors.prefix(4)) { e in
                    Button("Open with \(e.version)") { Task { await state.open(row, version: e.version) } }
                }
            }
            Button("Cancel", role: .cancel) {}
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
