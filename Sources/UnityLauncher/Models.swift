import Foundation

/// Standard Unity CLI JSON envelope: `{ success, command, data, errors, warnings }`.
struct Envelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let errors: [CLIErrorItem]
    let warnings: [String]
}

struct CLIErrorItem: Decodable, Hashable, Sendable {
    let code: String
    let message: String
}

struct Project: Decodable, Identifiable, Hashable, Sendable {
    var id: String { path }
    let title: String
    let path: String
    let version: String
    let architecture: String?
    let buildTarget: String?
    let renderPipeline: String?
    let vcsProvider: String?
    /// Milliseconds since 1970, as written by the Hub / CLI.
    let lastModified: Double?
    let isFavorite: Bool?

    var modified: Date? { lastModified.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

struct EditorInstall: Decodable, Identifiable, Hashable, Sendable {
    var id: String { location }
    let version: String
    let architecture: String
    let location: String
    let modules: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case version, architecture, location, modules
        case isDefault = "default"
    }
}

struct Release: Decodable, Identifiable, Hashable, Sendable {
    var id: String { version + architecture }
    let version: String
    let architecture: String
    let stream: String
    let lts: Bool
    let installed: Bool
}

/// `6000.3.16f1` → (6000, 3, 16, "f", 1). Type letters sort alphabetically: a < b < f < p.
struct UnityVersion: Comparable, Hashable, Sendable {
    let major: Int, minor: Int, patch: Int
    let type: Character
    let build: Int

    init?(_ string: String) {
        guard let m = string.firstMatch(of: /^(\d+)\.(\d+)\.(\d+)([abfpx])(\d+)/),
              let major = Int(m.1), let minor = Int(m.2), let patch = Int(m.3), let build = Int(m.5)
        else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
        self.type = Character(String(m.4)); self.build = build
    }

    static func < (l: Self, r: Self) -> Bool {
        (l.major, l.minor, l.patch, l.type, l.build) < (r.major, r.minor, r.patch, r.type, r.build)
    }

    /// Sort predicate: newest first, unparseable versions last.
    static func newerFirst(_ a: String, _ b: String) -> Bool {
        switch (UnityVersion(a), UnityVersion(b)) {
        case let (x?, y?): x > y
        case (_?, nil): true
        default: false
        }
    }

    /// Smallest installed version newer than `from` (ULP's "suggest next version" behaviour).
    static func suggestUpgrade(from: String, installed: [String]) -> String? {
        let current = UnityVersion(from)
        return installed
            .compactMap { s in UnityVersion(s).map { (s, $0) } }
            .filter { current == nil || $0.1 > current! }
            .min { $0.1 < $1.1 }?.0
    }
}
