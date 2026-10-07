import Foundation
import CryptoKit

struct ReleaseVersion: Comparable, Equatable {
    let components: [Int]
    let text: String
    init(_ value: String) throws {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count), pieces.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }), pieces.allSatisfy({ Int($0) != nil }) else {
            throw InputError.invalid("GitHub returned an unsupported release version: \(value).")
        }
        self.text = text
        self.components = pieces.map { Int($0)! } + Array(repeating: 0, count: 3 - pieces.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.components == rhs.components }
}
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int
        let digest: String?
        let browser_download_url: String
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    func updateAsset(current: String, arch: String) throws -> Asset? {
        guard !draft, !prerelease else { throw InputError.invalid("GitHub did not return a stable release. No changes were made.") }
        let version = try ReleaseVersion(tag_name)
        guard version > (try ReleaseVersion(current)) else { return nil }
        return try asset(arch: arch)
    }
    func asset(arch: String) throws -> Asset {
        _ = try ReleaseVersion(tag_name)
        guard !draft, !prerelease else { throw InputError.invalid("Only stable releases can be installed.") }
        let platform = arch == "arm64" ? "aarch64" : "x86_64"
        let name = "scrcpy-macos-\(platform)-\(tag_name).tar.gz"
        guard let asset = assets.first(where: { $0.name == name }), asset.size > 0, asset.size <= 128 * 1024 * 1024 else {
            throw InputError.invalid("This release has no supported macOS download for this Mac. Your current version is unchanged.")
        }
        let expected = "https://github.com/Genymobile/scrcpy/releases/download/\(tag_name)/\(name)"
        guard asset.browser_download_url == expected else { throw InputError.invalid("Unexpected release download URL. Update cancelled.") }
        guard let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71,
              digest.dropFirst(7).allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else {
            throw InputError.invalid("GitHub has not published a SHA-256 digest for this download. It cannot be installed safely yet.")
        }
        return asset
    }
}

// The app bundle is immutable. Only an atomic pointer to a fully validated engine changes.
struct EngineStore {
    struct Engine: Codable, Equatable { let folder: String; let version: String }
    struct Manifest: Codable { let current: Engine; let previous: Engine? }
    static let bundledVersion = "5.0"
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    let base: URL
    let bundledRoot: URL
    let arch: String
    init(base: URL? = nil, bundledRoot: URL? = nil, arch: String = Self.architecture) {
        self.arch = arch
        self.base = base ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Scrcpy Desk/Engines/\(arch)")
        self.bundledRoot = bundledRoot ?? Bundle.main.resourceURL!.appendingPathComponent("Engine/\(arch)")
    }
    var manifestURL: URL { base.appendingPathComponent("current.json") }
    var manifest: Manifest? {
        guard let data = try? Data(contentsOf: manifestURL), let manifest = try? JSONDecoder().decode(Manifest.self, from: data), usable(manifest.current) else { return nil }
        return manifest
    }
    func valid(_ engine: Engine) -> Bool {
        guard !engine.folder.isEmpty, !engine.folder.hasPrefix("."), engine.folder.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }), (try? ReleaseVersion(engine.version)) != nil else { return false }
        return ["scrcpy", "adb", "scrcpy-server"].allSatisfy { FileManager.default.fileExists(atPath: base.appendingPathComponent(engine.folder).appendingPathComponent($0).path) }
    }
    // A frontend upgrade must not keep using an older downloaded engine instead
    // of the newer bundled one. Retain the files, but treat the bundle as a floor.
    func usable(_ engine: Engine) -> Bool {
        guard valid(engine), let version = try? ReleaseVersion(engine.version),
              let bundled = try? ReleaseVersion(Self.bundledVersion) else { return false }
        return version >= bundled
    }
    var root: URL { manifest.map { base.appendingPathComponent($0.current.folder) } ?? bundledRoot }
    var version: String { manifest?.current.version ?? Self.bundledVersion }
    var rollbackVersion: String { manifest?.previous.flatMap { usable($0) ? $0.version : nil } ?? Self.bundledVersion }
    var isUpdated: Bool { manifest != nil }
    func rollback() throws {
        guard let current = manifest else { return }
        if let previous = current.previous, usable(previous) {
            try JSONEncoder().encode(Manifest(current: previous, previous: nil)).write(to: manifestURL, options: .atomic)
        } else { try FileManager.default.removeItem(at: manifestURL) }
    }
    func install(archive: URL, release: GitHubRelease) throws -> String {
        let asset = try release.asset(arch: arch)
        let version = try ReleaseVersion(release.tag_name).text
        let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard bytes.count == asset.size, Self.sha256(bytes) == String(asset.digest!.dropFirst(7)).lowercased() else {
            throw InputError.invalid("Download checksum or size did not match GitHub. Your current engine was kept.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let folder = "\(version)-\(UUID().uuidString)"
        let destination = base.appendingPathComponent(folder)
        try fm.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var committed = false
        defer { if !committed { try? fm.removeItem(at: destination) } }
        let prefix = String(asset.name.dropLast(".tar.gz".count))
        // Extract explicit members to stdout, then write regular files ourselves. Tar never
        // chooses filesystem paths or creates links, so traversal/symlink entries cannot escape.
        for name in ["scrcpy", "adb", "scrcpy-server", "LICENSE", "scrcpy.png", "disconnected.png", "scrcpy.1"] {
            let data = try Self.capture(URL(fileURLWithPath: "/usr/bin/tar"), ["-xOzf", archive.path, "\(prefix)/\(name)"], maxBytes: 128 * 1024 * 1024)
            guard !data.isEmpty else { throw InputError.invalid("The release archive is missing \(name).") }
            let file = destination.appendingPathComponent(name)
            try data.write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: ["scrcpy", "adb"].contains(name) ? 0o700 : 0o600], ofItemAtPath: file.path)
        }
        var env = ProcessInfo.processInfo.environment
        env["ADB"] = destination.appendingPathComponent("adb").path
        env["SCRCPY_SERVER_PATH"] = destination.appendingPathComponent("scrcpy-server").path
        let reported = String(decoding: try Self.capture(destination.appendingPathComponent("scrcpy"), ["--version"], environment: env), as: UTF8.self)
        let fields = reported.split(whereSeparator: { $0.isWhitespace })
        guard fields.count >= 2, fields[0] == "scrcpy", (try? ReleaseVersion(String(fields[1]))) == (try ReleaseVersion(version)) else {
            throw InputError.invalid("The downloaded scrcpy version could not be verified on this Mac. Your previous version was kept.")
        }
        let adb = String(decoding: try Self.capture(destination.appendingPathComponent("adb"), ["version"]), as: UTF8.self)
        guard adb.contains("Android Debug Bridge version") else { throw InputError.invalid("The downloaded ADB could not run on this Mac.") }
        let help = try Self.capture(destination.appendingPathComponent("scrcpy"), ["--help"], environment: env)
        let helpText = String(decoding: help, as: UTF8.self)
        for flag in ["--serial", "--max-size", "--max-fps", "--video-bit-rate", "--video-codec", "--audio-source", "--audio-codec", "--keyboard", "--mouse", "--record", "--capture-orientation"] {
            guard helpText.contains(flag) else { throw InputError.invalid("This scrcpy release changed required options. Keep using the current engine until the frontend is updated.") }
        }
        try help.write(to: destination.appendingPathComponent("scrcpy-help.txt"), options: .atomic)
        let state = Manifest(current: Engine(folder: folder, version: version), previous: manifest?.current)
        try JSONEncoder().encode(state).write(to: manifestURL, options: .atomic)
        committed = true
        return version
    }
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func capture(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil, maxBytes: Int = 2 * 1024 * 1024) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments; process.environment = environment
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        defer { timeout.cancel() }
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
            guard data.count + chunk.count <= maxBytes else {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }; process.waitUntilExit()
                throw InputError.invalid("Release contents exceeded the expected size. Update cancelled.")
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InputError.invalid("The release could not be extracted or run on this Mac (\(executable.lastPathComponent), exit \(process.terminationStatus)). Your current version was kept.") }
        return data
    }
}

final class EngineUpdater {
    static let latestURL = URL(string: "https://api.github.com/repos/Genymobile/scrcpy/releases/latest")!
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        session = URLSession(configuration: configuration)
    }
    func latest() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.2"
        request.setValue("ScrcpyDesk/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
    func download(_ asset: GitHubRelease.Asset) async throws -> URL {
        let (file, response) = try await session.download(from: URL(string: asset.browser_download_url)!)
        do { try Self.check(response) } catch { try? FileManager.default.removeItem(at: file); throw error }
        let ownedFile = FileManager.default.temporaryDirectory.appendingPathComponent("scrcpy-update-\(UUID().uuidString).tar.gz")
        try FileManager.default.moveItem(at: file, to: ownedFile)
        return ownedFile
    }
    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw InputError.invalid("Invalid response from GitHub.") }
        guard http.statusCode == 200 else {
            if [403, 429].contains(http.statusCode) { throw InputError.invalid("GitHub's request limit was reached. Try again later; your current engine is unchanged.") }
            throw InputError.invalid("GitHub returned HTTP \(http.statusCode). Try again later.")
        }
    }
}
