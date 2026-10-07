import SwiftUI

/// Folders and utilities that don't belong to one project (ULP's Tools menu).
struct ToolsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section("Folders") {
                ForEach(Local.Folder.allCases) { folder in
                    LabeledContent(folder.rawValue) {
                        HStack {
                            Text(folder.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Button("Open") { Mac.open(folder.url) }.controlSize(.small)
                        }
                    }
                }
            }
            Section("Editors") {
                LabeledContent("Register an editor installed outside Unity Hub") {
                    Button("Locate Unity Editor…") {
                        if let url = Mac.chooseApp(message: "Choose a Unity.app to register") {
                            Task { await state.cliAction(["editors", "add", url.path]) }
                        }
                    }
                }
            }
            Section("Android") {
                LabeledContent("Unity log from a connected device") {
                    Button("ADB Logcat") { state.adbLogcat() }
                }
            }
            Section("Diagnostics") {
                LabeledContent("Check the Unity CLI, sign-in and installed editors") {
                    Button("Unity Doctor") { Task { await state.doctor() } }
                }
            }
        }
        .formStyle(.grouped)
    }
}
