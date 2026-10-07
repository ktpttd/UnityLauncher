import SwiftUI

/// Folders and utilities that don't belong to one project (ULP's Tools bar).
struct ToolsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
            GridRow {
                Text("Folders").foregroundStyle(.secondary)
                HStack {
                    ForEach(Local.Folder.allCases) { folder in
                        Button(folder.rawValue) { Mac.open(folder.url) }
                            .help(folder.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    }
                }
            }
            GridRow {
                Text("Tools").foregroundStyle(.secondary)
                HStack {
                    Button("Locate Unity Editor…") {
                        if let url = Mac.chooseApp(message: "Choose a Unity.app to register") {
                            Task { await state.cliAction(["editors", "add", url.path]) }
                        }
                    }
                    .help("Register an editor installed outside Unity Hub")
                    Button("ADB Logcat") { state.adbLogcat() }
                        .help("Unity log from a connected Android device")
                    Button("Unity Doctor") { Task { await state.doctor() } }
                        .help("Check the Unity CLI, sign-in and installed editors")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
