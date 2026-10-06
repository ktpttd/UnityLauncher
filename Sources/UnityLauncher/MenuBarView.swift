import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if state.recentProjects.isEmpty {
            Text("No projects")
        }
        ForEach(state.recentProjects) { row in
            Button("\(row.project.title)  —  \(row.project.version)") { Task { await state.open(row) } }
        }
        Divider()
        Button("Show Launcher") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Refresh") { Task { await state.refresh() } }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
