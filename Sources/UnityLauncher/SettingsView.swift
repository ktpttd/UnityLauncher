import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("cliPath") private var cliPath = ""
    @AppStorage("hideAfterOpen") private var hideAfterOpen = false
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("newProjectFolder") private var newProjectFolder = NSString(string: "~/UnityProjects").expandingTildeInPath
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Unity CLI") {
                TextField("Custom path", text: $cliPath, prompt: Text("Auto-detect (~/.unity/bin/unity)"))
                    .onSubmit { state.relocateCLI() }
                LabeledContent("Using") {
                    Text(state.cli?.executable.path ?? "Not found").foregroundStyle(state.cli == nil ? .red : .secondary)
                }
                Button("Detect Again") { state.relocateCLI(); Task { await state.refresh() } }
            }
            Section("Projects") {
                Toggle("Show projects whose folder is missing", isOn: $state.showMissing)
                Toggle("Hide launcher after opening a project", isOn: $hideAfterOpen)
                LabeledContent("New project folder") {
                    HStack {
                        Text(newProjectFolder).truncationMode(.head).lineLimit(1)
                        Button("Choose…") { if let url = Mac.chooseFolder(message: "Default folder for new projects") { newProjectFolder = url.path } }
                    }
                }
            }
            Section("App") {
                Toggle("Show in menu bar", isOn: $showMenuBar)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                        catch { state.errorMessage = "Launch at login needs the bundled app (scripts/bundle.sh). \(error.localizedDescription)" }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
