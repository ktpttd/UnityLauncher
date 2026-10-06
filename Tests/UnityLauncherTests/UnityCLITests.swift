import Foundation
import Testing
@testable import UnityLauncher

/// Writes an executable shell script standing in for the `unity` binary.
func fakeCLI(_ body: String) throws -> UnityCLI {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("unity")
    try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return UnityCLI(executable: url)
}

@Test func passesArgsVerbatimWithGlobalFlags() async throws {
    // Prints every argument as a JSON array element, plus the pager env var.
    let cli = try fakeCLI(#"""
    printf '{"success":true,"data":['
    sep=""; for a in "$@"; do printf '%s"%s"' "$sep" "$a"; sep=","; done
    printf ',"pager=%s"],"errors":[],"warnings":[]}' "$UNITY_NO_PAGER"
    """#)
    let args = try await cli.run(["projects", "add", "/Users/dev/My Game ✨"], as: [String].self)
    #expect(args == ["--no-banner", "--non-interactive", "--format", "json",
                     "projects", "add", "/Users/dev/My Game ✨", "pager=1"])
}

@Test func skipsNoiseBeforeJSON() async throws {
    let cli = try fakeCLI(#"echo 'Update available: 1.0.1'; echo '{"success":true,"data":[1],"errors":[],"warnings":[]}'"#)
    #expect(try await cli.run(["x"], as: [Int].self) == [1])
}

@Test func failureEnvelopeThrowsCLIError() async throws {
    let cli = try fakeCLI(#"echo '{"success":false,"data":null,"errors":[{"code":"X","message":"boom"}],"warnings":[]}'; exit 6"#)
    await #expect(throws: CLIError.failed(code: "X", message: "boom")) {
        try await cli.run(["x"], as: [Int].self)
    }
}

@Test func emptyOutputWithNonZeroExitThrowsExited() async throws {
    let cli = try fakeCLI("echo oops >&2; exit 1")
    await #expect(throws: CLIError.exited(1, "oops")) {
        try await cli.run(["x"], as: [Int].self)
    }
}

@Test func streamYieldsFramesInOrder() async throws {
    let cli = try fakeCLI(#"""
    echo '{"type":"progress","message":"Downloading","pct":10}'
    echo '{"type":"progress","message":"Installing","pct":50}'
    echo '{"type":"result","success":true,"errors":[]}'
    """#)
    var frames: [Frame] = []
    for try await f in cli.stream(["install", "6000.0.1f1"]) { frames.append(f) }
    #expect(frames.map(\.type) == ["progress", "progress", "result"])
    #expect(frames[1].pct == 50)
    #expect(frames[2].success == true)
}

@Test func streamThrowsWhenProcessDiesWithoutResult() async throws {
    let cli = try fakeCLI(#"echo '{"type":"progress","message":"Downloading"}'; exit 6"#)
    var count = 0
    await #expect(throws: CLIError.self) {
        for try await _ in cli.stream(["install"]) { count += 1 }
    }
    #expect(count == 1)
}

@Test func streamUsesNDJSONFormat() async throws {
    let cli = try fakeCLI(#"echo "{\"type\":\"result\",\"success\":true,\"message\":\"$4\"}""#)
    var last: Frame?
    for try await f in cli.stream(["x"]) { last = f }
    #expect(last?.message == "ndjson")
}

/// `unity open` prints nothing on success, even with --format json.
@Test func silentSuccessIsSuccessForRunVoidOnly() async throws {
    let cli = try fakeCLI("exit 0")
    try await cli.runVoid(["open", "/p"])
    await #expect(throws: CLIError.badOutput("missing data")) {
        try await cli.run(["projects", "list"], as: [Int].self)
    }
}

@Test func runVoidAcceptsNullData() async throws {
    try await fakeCLI(#"echo '{"success":true,"data":null,"errors":[],"warnings":[]}'"#).runVoid(["projects", "pin", "/p"])
    await #expect(throws: CLIError.failed(code: "NOPE", message: "no")) {
        try await fakeCLI(#"echo '{"success":false,"data":null,"errors":[{"code":"NOPE","message":"no"}],"warnings":[]}'"#).runVoid(["x"])
    }
}

@Test func locatePrefersExistingOverride() throws {
    let cli = try fakeCLI("true")
    #expect(UnityCLI.locate(override: cli.executable.path) == cli.executable)
    #expect(UnityCLI.locate(override: "/nope/unity", candidates: []) == nil)
}
