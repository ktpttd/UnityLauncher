import Foundation

/// Picks the lines that explain a failed Unity build out of a log that can run to 100k lines.
/// Only specific failure patterns count: Unity logs harmless exceptions during successful builds too.
enum BuildErrors {
    static func find(in log: String) -> [String] {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var found: [String] = []
        func add(_ line: String) { if !found.contains(line) { found.append(line) } }
        for (i, line) in lines.enumerated() where found.count < 4 {
            let next = i + 1 < lines.count ? lines[i + 1] : ""
            if line.contains(": error CS") || line == "Scripts have compiler errors."
                || line.hasPrefix("Error building Player") || line.hasPrefix("BuildFailedException:")
                || line.contains("Unity Launcher:") {
                add(line)
            } else if line.hasPrefix("UnityException:") {
                add(line)
                // The reason often follows on its own line; stack frames contain "(".
                if !next.isEmpty, !next.contains("(") { add(next) }
            } else if line == "* What went wrong:", !next.isEmpty {
                add(next) // Gradle
            }
        }
        return Array(found.prefix(4))
    }

    /// The log `unity build` just wrote: the newest Logs/build-*.log.
    static func latestLog(project: URL) -> URL? {
        let logs = (try? FileManager.default.contentsOfDirectory(at: project.appendingPathComponent("Logs"),
                                                                  includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return logs.filter { $0.lastPathComponent.hasPrefix("build-") && $0.pathExtension == "log" }
            .max { modified($0) < modified($1) }
    }
}
