import SwiftUI

struct TasksView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tasks").font(.headline)
                Spacer()
                Button("Clear Finished") { state.tasks.removeAll { $0.state != .running } }
                    .disabled(!state.tasks.contains { $0.state != .running })
            }
            .padding(8)
            Divider()
            List(state.tasks) { TaskRow(item: $0) }
                .overlay {
                    if state.tasks.isEmpty { ContentUnavailableView("No Tasks", systemImage: "checklist") }
                }
        }
    }
}

private struct TaskRow: View {
    let item: TaskItem
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                switch item.state {
                case .running: Image(systemName: "hourglass").foregroundStyle(.blue)
                case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                Text(item.title).bold().lineLimit(1)
                Spacer()
                if item.state == .running { Button("Stop") { item.stop() }.controlSize(.small) }
            }
            Group {
                if item.state == .running {
                    Text(item.startedAt, style: .timer).monospacedDigit()
                } else if let end = item.finishedAt {
                    let took = formatDuration(end.timeIntervalSince(item.startedAt))
                    Text(item.state == .succeeded ? "Done in \(took)" : "Ended after \(took)")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let summary = item.summary {
                HStack {
                    Text(summary).font(.callout.weight(.semibold)).textSelection(.enabled)
                    if let output = item.output {
                        Button("Show") { Mac.reveal(output.path) }.controlSize(.small)
                    }
                }
            }
            if item.state == .running {
                if let pct = item.pct { ProgressView(value: min(pct, 100), total: 100) }
                else { ProgressView().progressViewStyle(.linear) }
            }
            if case .failed(let message) = item.state {
                Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            DisclosureGroup("Log (\(item.log.count))", isExpanded: $expanded) {
                ScrollView {
                    Text(item.log.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
            .font(.caption)
            if !expanded, let last = item.log.last {
                Text(last).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
