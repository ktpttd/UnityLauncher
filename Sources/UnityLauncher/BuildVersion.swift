import Foundation

/// Player Settings' version, Android version code and iOS build number, read from and written back to
/// either ProjectSettings.asset or a Build Profile's override (`- line: '|   key: value'`).
struct BuildVersion: Equatable {
    var version: String
    var androidCode: String
    var iosBuild: String

    /// The file a build reads these from: the profile when it overrides Player Settings, else the project's.
    static func file(project: URL, profile: String?) -> URL {
        project.appendingPathComponent(profile ?? "ProjectSettings/ProjectSettings.asset")
    }

    static func read(_ text: String) -> BuildVersion? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let at = locate(lines)
        func get(_ index: Int?, _ key: String) -> String? {
            index.flatMap { value(content(lines[$0]), key: key) }.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        guard let version = get(at.version, "bundleVersion") else { return nil }
        return BuildVersion(version: version, androidCode: get(at.code, "AndroidBundleVersionCode") ?? "",
                            iosBuild: get(at.ios, "iPhone") ?? "")
    }

    /// Replaces only the three values in place; every other line stays byte-for-byte the same.
    func write(into text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let at = Self.locate(lines.map { Substring($0) })
        for (index, key, new) in [(at.version, "bundleVersion", version), (at.code, "AndroidBundleVersionCode", androidCode), (at.ios, "iPhone", iosBuild)] {
            guard let i = index, !new.isEmpty,
                  let old = Self.value(Self.content(Substring(lines[i])), key: key),
                  let range = lines[i].range(of: "\(key): \(old)") else { continue }
            lines[i].replaceSubrange(range, with: "\(key): \(new)")
        }
        return lines.joined(separator: "\n")
    }

    /// "62" → "63", "62.1" → "62.2"; anything else is returned unchanged.
    static func bump(_ value: String) -> String {
        var parts = value.split(separator: ".").map(String.init)
        guard let last = parts.last.flatMap({ Int($0) }) else { return value }
        parts[parts.count - 1] = String(last + 1)
        return parts.joined(separator: ".")
    }

    /// Why Unity would reject these values, or nil if they're fine.
    var problem: String? {
        if version.isEmpty || version.contains(where: { !($0.isLetter || $0.isNumber || ".-+".contains($0)) }) {
            return "Version may only contain letters, digits, '.', '-' and '+'."
        }
        if !androidCode.isEmpty, (Int(androidCode) ?? 0) < 1 || (Int(androidCode) ?? 0) > 2_100_000_000 {
            return "Version code must be a whole number from 1 to 2100000000."
        }
        if !iosBuild.isEmpty, iosBuild.wholeMatch(of: /\d+(\.\d+){0,2}/) == nil {
            return "Build must be like 62 or 62.1."
        }
        return nil
    }

    // MARK: Line parsing

    /// Line text without a profile's `- line: '|` wrapper, so both formats parse alike.
    private static func content(_ line: Substring) -> Substring {
        guard let r = line.range(of: "- line: '|") else { return line }
        let c = line[r.upperBound...]
        return c.hasSuffix("'") ? c.dropLast() : c
    }

    /// `key`'s value when the line is exactly that key (so `bundleVersion` never matches `tvOSBundleVersion`).
    private static func value(_ content: Substring, key: String) -> Substring? {
        let t = content.drop { $0 == " " }
        return t.hasPrefix(key + ": ") ? t.dropFirst(key.count + 2) : nil
    }

    private static func locate(_ lines: [Substring]) -> (version: Int?, code: Int?, ios: Int?) {
        var version: Int?, code: Int?, ios: Int?
        var buildNumberIndent: Int?  // inside `buildNumber:`, whose iPhone entry is the iOS build
        for (i, line) in lines.enumerated() {
            let c = content(line)
            let indent = c.prefix { $0 == " " }.count
            if let parent = buildNumberIndent {
                if indent <= parent { buildNumberIndent = nil }
                else if ios == nil, value(c, key: "iPhone") != nil { ios = i; continue }
            }
            if version == nil, value(c, key: "bundleVersion") != nil { version = i }
            if code == nil, value(c, key: "AndroidBundleVersionCode") != nil { code = i }
            if c.drop(while: { $0 == " " }) == "buildNumber:" { buildNumberIndent = indent }
        }
        return (version, code, ios)
    }
}
