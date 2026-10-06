import Foundation
import Testing
@testable import UnityLauncher

let sampleLog = """
noise before
Build Report
Uncompressed usage by category (Percentages based on user generated assets only):
Textures               1.0 mb\t 50.0%
Scripts                1.0 mb\t 50.0%
Total User Assets      2.0 mb\t 100.0%
Complete build size    9.0 mb
Used Assets and files from the Resources folder, sorted by uncompressed size:
 1.0 mb\t 50.0% Assets/Old.png
-------------------------------------------------------------------------------
Build completed with a result of 'Succeeded' in 12 seconds (12000 ms)
more noise
Build Report
Uncompressed usage by category (Percentages based on user generated assets only):
Textures               6.9 mb\t 47.2%
Included DLLs          5.3 mb\t 36.6%
Total User Assets      14.5 mb\t 100.0%
Complete build size    40.4 mb
Used Assets and files from the Resources folder, sorted by uncompressed size:
 3.0 mb\t 20.7% Assets/Textures/Big Background.png
 1.2 mb\t 8.2% Resources/unity_builtin_extra
 garbage row without tab
-------------------------------------------------------------------------------
"""

@Test func parsesEveryReportInLog() {
    let reports = BuildReport.parseAll(sampleLog)
    #expect(reports.count == 2)
    let last = reports[1]
    #expect(last.stats.map(\.category) == ["Textures", "Included DLLs", "Total User Assets", "Complete build size"])
    #expect(last.stats.last?.size == "40.4 mb")
    #expect(last.stats.last?.percent == nil)
    #expect(last.stats.first?.percent == "47.2%")
    #expect(last.items.count == 2)
    #expect(last.items[0].size == "3.0 mb")
    #expect(last.items[0].percent == "20.7%")
    #expect(last.items[0].path == "Assets/Textures/Big Background.png")
}

@Test func noReportInLogYieldsEmpty() {
    #expect(BuildReport.parseAll("Starting Unity...\nExiting batchmode").isEmpty)
}

@Test func latestReportPrefersNewestLogWithAReport() throws {
    let project = try unityProject()
    let logs = project.appendingPathComponent("Logs")
    let older = logs.appendingPathComponent("build-StandaloneOSX-1.log")
    let newer = logs.appendingPathComponent("build-StandaloneOSX-2.log")
    try write(sampleLog, to: older)
    try write("build failed, no report", to: newer)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: older.path)
    let editorLog = try tempDir().appendingPathComponent("Editor.log")
    try write("other project log\n" + sampleLog.replacingOccurrences(of: "Big Background", with: "Other"), to: editorLog)

    let found = try #require(BuildReport.latest(project: project, editorLog: editorLog))
    #expect(found.source.resolvingSymlinksInPath() == older.resolvingSymlinksInPath())
    #expect(found.report.items.first?.path == "Assets/Textures/Big Background.png")
}

@Test func editorLogCountsOnlyWhenItMentionsTheProject() throws {
    let project = try unityProject()
    let editorLog = try tempDir().appendingPathComponent("Editor.log")
    try write("-projectpath /somewhere/else\n" + sampleLog, to: editorLog)
    #expect(BuildReport.latest(project: project, editorLog: editorLog) == nil)
    try write("-projectpath \(project.path)\n" + sampleLog, to: editorLog)
    #expect(BuildReport.latest(project: project, editorLog: editorLog)?.source == editorLog)
}
