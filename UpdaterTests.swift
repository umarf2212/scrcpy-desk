import Foundation

@main struct UpdaterTests {
    static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        func rejects(_ message: String, _ operation: () throws -> Void) { do { try operation(); preconditionFailure(message) } catch { checks += 1 } }
        check(try ReleaseVersion("v4.10") > ReleaseVersion("4.9"), "numeric version ordering")
        check(try ReleaseVersion("v4.1") == ReleaseVersion("4.1.0"), "normalized versions")
        check(try ReleaseVersion("4.0.9") < ReleaseVersion("4.1"), "patch ordering")
        for invalid in ["v4.2-beta", "../4", "4..2", "", "9999999999999999999999", "4.1.0.1"] {
            rejects("invalid release accepted") { _ = try ReleaseVersion(invalid) }
        }
        let releaseURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let archive = URL(fileURLWithPath: CommandLine.arguments[2])
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(contentsOf: releaseURL))
        check(try release.updateAsset(current: "4.1", arch: "arm64") == nil, "current release no update")
        check(try release.updateAsset(current: "5.0", arch: "arm64") == nil, "never downgrade")
        check(try release.updateAsset(current: "4.0", arch: "arm64")?.name.contains("aarch64") == true, "arm update selection")
        check(try release.updateAsset(current: "4.0", arch: "x86_64")?.name.contains("x86_64") == true, "intel update selection")
        func changed(_ edit: (inout [String: Any]) -> Void) throws -> GitHubRelease {
            var object = try JSONSerialization.jsonObject(with: Data(contentsOf: releaseURL)) as! [String: Any]
            edit(&object)
            return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let beta = try changed { $0["prerelease"] = true }
        rejects("beta installed") { _ = try beta.updateAsset(current: "4.0", arch: "arm64") }
        let missing = try changed { $0["assets"] = [] }
        rejects("missing asset accepted") { _ = try missing.updateAsset(current: "4.0", arch: "arm64") }
        let noDigest = try changed { object in
            var assets = object["assets"] as! [[String: Any]]
            for i in assets.indices { assets[i].removeValue(forKey: "digest") }; object["assets"] = assets
        }
        rejects("missing digest accepted") { _ = try noDigest.asset(arch: "arm64") }
        let badURL = try changed { object in
            var assets = object["assets"] as! [[String: Any]]
            for i in assets.indices { assets[i]["browser_download_url"] = "https://example.com/download" }; object["assets"] = assets
        }
        rejects("untrusted origin accepted") { _ = try badURL.asset(arch: "arm64") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("scrcpy-updater-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = EngineStore(base: base, bundledRoot: URL(fileURLWithPath: "/bundled"))
        check(store.version == "4.1" && store.root.path == "/bundled", "bundled default")
        let installed = try store.install(archive: archive, release: release)
        check(installed == "4.1" && store.isUpdated && store.root != store.bundledRoot, "official archive installed")
        check(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("scrcpy-help.txt").path), "help generated")
        let initial = store.manifest!.current
        let wrongHash = try changed { object in
            var assets = object["assets"] as! [[String: Any]]
            for i in assets.indices { assets[i]["digest"] = "sha256:" + String(repeating: "0", count: 64) }; object["assets"] = assets
        }
        rejects("wrong digest installed") { _ = try store.install(archive: archive, release: wrongHash) }
        check(store.manifest!.current == initial, "failed update preserves active pointer")
        let badArchive = base.appendingPathComponent("bad.tar.gz")
        let garbage = Data("not a tar archive".utf8); try garbage.write(to: badArchive)
        let matchingGarbage = try changed { object in
            var assets = object["assets"] as! [[String: Any]]
            for i in assets.indices { assets[i]["digest"] = "sha256:" + EngineStore.sha256(garbage); assets[i]["size"] = garbage.count }; object["assets"] = assets
        }
        rejects("bad archive accepted") { _ = try store.install(archive: badArchive, release: matchingGarbage) }
        check(store.manifest!.current == initial, "extraction failure preserves active pointer")
        _ = try store.install(archive: archive, release: release)
        check(store.manifest!.previous == initial, "previous engine retained")
        try store.rollback()
        check(store.manifest!.current == initial, "rollback restores previous engine")
        try store.rollback()
        check(!store.isUpdated && store.root.path == "/bundled", "fallback to bundled")
        try Data("broken json".utf8).write(to: store.manifestURL)
        check(store.root.path == "/bundled", "corrupt manifest safely falls back")
        check(!store.valid(.init(folder: "../outside", version: "4.1")), "manifest path traversal rejected")
        for status in [403, 404, 429, 500] {
            let response = HTTPURLResponse(url: EngineUpdater.latestURL, statusCode: status, httpVersion: nil, headerFields: nil)!
            rejects("HTTP failure accepted") { try EngineUpdater.check(response) }
        }
        print("Passed \(checks) updater checks, including verified installation of the official archive and rollback.")
        if CommandLine.arguments.contains("--live") {
            let updater = EngineUpdater()
            let live = try await updater.latest()
            let asset = try live.asset(arch: EngineStore.architecture)
            let downloaded = try await updater.download(asset)
            defer { try? FileManager.default.removeItem(at: downloaded) }
            check(EngineStore.sha256(try Data(contentsOf: downloaded)) == String(asset.digest!.dropFirst(7)), "live download checksum")
            print("Live GitHub check and verified download passed: \(live.tag_name).")
        }
    }
}
