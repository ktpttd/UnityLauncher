import SwiftUI

/// Drive running Unity 6 Editors through `unity status` / `unity command` (Pipeline package).
struct LiveView: View {
    @Environment(AppState.self) private var state
    @State private var model: LiveModel?

    var body: some View {
        Group {
            if let model { LiveContent(model: model) } else { ProgressView() }
        }
        .task {
            if model == nil { model = LiveModel(cli: state.cli) }
        }
    }
}

private struct LiveContent: View {
    @Bindable var model: LiveModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .background(.red.opacity(0.08))
            }
            if model.instances.isEmpty {
                ContentUnavailableView {
                    Label("No live Editor", systemImage: "bolt.slash")
                } description: {
                    Text("Open a Unity 6 project that has the Pipeline package.\nProjects tab → right-click a project → Enable Live Control.")
                } actions: {
                    Button("Check Again") { Task { await model.refreshInstances() } }
                }
            } else {
                header
                Divider()
                HSplitView {
                    consolePane.frame(minWidth: 320)
                    VStack(spacing: 0) {
                        evalPane
                        Divider()
                        commandPane
                    }
                    .frame(minWidth: 320)
                }
            }
        }
        .task(id: model.selected) {
            await model.loadCatalog()
        }
        .task {
            // Poll while the tab is visible; SwiftUI cancels this when it disappears.
            while !Task.isCancelled {
                await model.refreshInstances()
                await model.poll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("Editor", selection: $model.selected) {
                ForEach(model.instances) { i in
                    Text("\(URL(fileURLWithPath: i.project).lastPathComponent) — \(i.version ?? "") (\(i.state))").tag(Optional(i.project))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320)
            if let s = model.status {
                Text(s.compiling ? "Compiling…" : (s.playMode ?? "").capitalized)
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(s.playMode == "playing" ? Color.green.opacity(0.25) : Color.secondary.opacity(0.15), in: .capsule)
            }
            Spacer()
            Group {
                Button("Play", systemImage: "play.fill") { Task { await model.run("editor_play") } }
                Button("Pause", systemImage: "pause.fill") { Task { await model.run("editor_pause") } }
                Button("Stop", systemImage: "stop.fill") { Task { await model.run("editor_stop") } }
                Divider().frame(height: 16)
                Button("Save All", systemImage: "square.and.arrow.down") { Task { await model.run("save_all") } }
                Button("Recompile", systemImage: "hammer") { Task { await model.run("recompile") } }
                Button("Screenshot", systemImage: "camera") { Task { await model.screenshot() } }
            }
            .labelStyle(.iconOnly)
            .disabled(model.busy)
        }
        .padding(8)
    }

    private var consolePane: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Level", selection: $model.level) {
                    Text("All").tag("log"); Text("Warnings").tag("warn"); Text("Errors").tag("error")
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240)
                if let c = model.counts {
                    Text("⚠︎ \(c.warn)  ⛔︎ \(c.error)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") { Task { await model.run("clear_console") } }.controlSize(.small)
            }
            .padding(6)
            List(model.console) { e in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: e.level == "error" ? "xmark.octagon.fill" : e.level == "warn" ? "exclamationmark.triangle.fill" : "info.circle")
                        .foregroundStyle(e.level == "error" ? .red : e.level == "warn" ? .yellow : .secondary)
                    Text(e.message).font(.system(.caption, design: .monospaced)).lineLimit(4).textSelection(.enabled)
                }
                .help(e.stackTrace ?? "")
            }
        }
    }

    private var evalPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("C# (eval)").font(.headline)
                Spacer()
                Button("Run") { Task { await model.eval() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.busy)
            }
            TextEditor(text: $model.evalCode)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 140)
                .border(.separator)
            Text(model.evalOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
    }

    private var commandPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Command").font(.headline)
                Text("\(model.catalog.count) available").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("get_scene_hierarchy --param value", text: $model.commandLine)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { Task { await model.runCommandLine() } }
                Button("Send") { Task { await model.runCommandLine() } }.disabled(model.busy)
            }
            let token = model.commandLine.split(separator: " ").first.map(String.init) ?? ""
            let matches = model.catalog.filter { !token.isEmpty && $0.name.hasPrefix(token) && $0.name != token }.prefix(6)
            if !matches.isEmpty {
                FlowButtons(items: Array(matches)) { model.commandLine = $0.name }
            }
            ScrollView {
                Text(model.commandOutput).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
    }
}

/// Suggestion chips for command names.
private struct FlowButtons: View {
    let items: [CommandInfo]
    let pick: (CommandInfo) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(items) { c in
                    Button(c.name) { pick(c) }.controlSize(.small).help(c.description ?? "")
                }
            }
        }
    }
}
