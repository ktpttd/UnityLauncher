import Foundation
import Testing
@testable import UnityLauncher

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func decodesProjects() throws {
    let env = try JSONDecoder().decode(Envelope<[Project]>.self, from: fixture("projects"))
    let projects = try #require(env.data)
    #expect(env.success)
    #expect(projects.count == 3)
    #expect(projects[0].title == "Capy_2D")
    #expect(projects[0].buildTarget == "iOS")
    #expect(projects[0].renderPipeline == "URP")
    #expect(projects[1].isFavorite == true)
    #expect(projects[2].architecture == nil)
    #expect(projects[0].modified == Date(timeIntervalSince1970: 1791302245.550))
}

@Test func decodesEditors() throws {
    let editors = try #require(try JSONDecoder().decode(Envelope<[EditorInstall]>.self, from: fixture("editors")).data)
    #expect(editors.count == 2)
    #expect(editors[0].isDefault)
    #expect(!editors[1].isDefault)
    #expect(editors[0].location.hasSuffix("Unity.app"))
}

@Test func decodesReleases() throws {
    let releases = try #require(try JSONDecoder().decode(Envelope<[Release]>.self, from: fixture("releases")).data)
    #expect(releases.map(\.stream) == ["ALPHA", "LTS"])
    #expect(releases[1].lts && releases[1].installed)
}

@Test func decodesFailureEnvelope() throws {
    let env = try JSONDecoder().decode(Envelope<[Project]>.self, from: fixture("error"))
    #expect(!env.success)
    #expect(env.data == nil)
    #expect(env.errors.first?.code == "INVALID_COMMAND_ARGS")
}

@Test func versionOrdering() throws {
    func v(_ s: String) throws -> UnityVersion { try #require(UnityVersion(s)) }
    #expect(try v("6000.3.16f1") > v("2022.3.62f3"))
    #expect(try v("2022.3.10f1") < v("2022.3.10p1"))
    #expect(try v("6000.7.0a1") < v("6000.7.0b1"))
    #expect(try v("6000.7.0b9") < v("6000.7.0f1"))
    #expect(try v("2022.3.9f1") < v("2022.3.10f1"))
}

@Test func versionParsingIsLenient() {
    #expect(UnityVersion("") == nil)
    #expect(UnityVersion("garbage") == nil)
    #expect(UnityVersion("2019.4.40f1c1") == UnityVersion("2019.4.40f1"))
}

@Test func suggestsNextInstalledVersion() {
    #expect(UnityVersion.suggestUpgrade(from: "2022.3.62f3", installed: ["6000.3.16f1", "2021.3.1f1", "6000.0.1f1"]) == "6000.0.1f1")
    #expect(UnityVersion.suggestUpgrade(from: "6000.3.16f1", installed: ["2022.3.62f3"]) == nil)
    #expect(UnityVersion.suggestUpgrade(from: "", installed: ["6000.3.16f1"]) == "6000.3.16f1")
}
