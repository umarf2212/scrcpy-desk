import Foundation
import Darwin

struct WirelessService: Identifiable, Equatable {
    enum Kind: String { case pairing = "_adb-tls-pairing._tcp.", connection = "_adb-tls-connect._tcp." }
    let name: String
    let kind: Kind
    let host: String
    let port: Int
    var id: String { name + kind.rawValue }
    var endpoint: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }
    // Android appends different random suffixes to the pairing and connection names.
    var deviceKey: String {
        guard name.hasPrefix("adb-"), let suffix = name.lastIndex(of: "-") else { return name }
        return String(name[..<suffix])
    }
    static func parse(_ text: String) -> [WirelessService] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count == 3,
                  let kind = Kind(rawValue: fields[1].hasSuffix(".") ? fields[1] : fields[1] + "."),
                  let endpoint = try? validateEndpoint(fields[2]), let colon = endpoint.lastIndex(of: ":"),
                  let port = Int(endpoint[endpoint.index(after: colon)...]) else { return nil }
            let host = String(endpoint[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return WirelessService(name: fields[0], kind: kind, host: host, port: port)
        }
    }
}

// Browse in the GUI process so macOS local-network permission belongs to the app,
// independently of ADB's daemon and its own mDNS backend.
final class WirelessDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var onChange: (([WirelessService]) -> Void)?
    var onError: ((String) -> Void)?
    private var browsers: [NetServiceBrowser] = []
    private var resolving: [String: NetService] = [:]
    private var resolved: [String: WirelessService] = [:]
    func start() {
        guard browsers.isEmpty else { return }
        for kind in [WirelessService.Kind.connection, .pairing] {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            browser.searchForServices(ofType: kind.rawValue, inDomain: "local.")
        }
    }
    func stop() {
        browsers.forEach { $0.stop() }; browsers.removeAll()
        resolving.values.forEach { $0.stop() }; resolving.removeAll(); resolved.removeAll()
    }
    private func key(_ service: NetService) -> String { service.name + service.type }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        resolving[key(service)] = service
        service.delegate = self
        service.resolve(withTimeout: 8)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        resolving.removeValue(forKey: key(service))?.stop()
        resolved.removeValue(forKey: key(service))
        onChange?(Array(resolved.values))
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        onError?("Wi-Fi discovery could not start (\(errorDict[NetService.errorCode]?.intValue ?? 0)). Check Local Network access in System Settings → Privacy & Security.")
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let kind = WirelessService.Kind(rawValue: sender.type), sender.port > 0 else { return }
        // Prefer IPv4. Use the advertised hostname when only IPv6 is available;
        // this preserves the interface scope for link-local IPv6 addresses.
        let ipv4 = sender.addresses?.compactMap { data -> String? in
            data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress, data.count >= MemoryLayout<sockaddr_in>.size,
                      base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family == sa_family_t(AF_INET) else { return nil }
                var address = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
                return String(cString: buffer)
            }
        }.first
        guard let host = ipv4 ?? sender.hostName else { return }
        resolved[key(sender)] = WirelessService(name: sender.name, kind: kind, host: host, port: sender.port)
        onChange?(Array(resolved.values))
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // Keep the browser alive; ADB polling can resolve a missed advertisement.
        resolving.removeValue(forKey: key(sender))
    }
    deinit { stop() }
}

// Keep network operations in a child of the GUI app. A shared, detached ADB
// daemon can retain a different macOS local-network permission identity.
// The private Unix socket also keeps this server separate from other ADB tools.
final class WirelessADBServer {
    let directory: URL
    var socket: String { "localfilesystem:" + directory.appendingPathComponent("adb.sock").path }
    private let lock = NSLock()
    private var process: Process?
    private var output: FileHandle?
    private var executable: URL?
    private var closed = false

    init() {
        directory = URL(fileURLWithPath: "/tmp").appendingPathComponent("scrcpy-wifi-\(getuid())-\(UUID().uuidString)")
    }

    func start(executable: URL, environment: [String: String]) throws {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { throw InputError.invalid("The Wi-Fi connection service is shutting down.") }
        if process?.isRunning == true, self.executable == executable { return }
        stopProcess()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let log = directory.appendingPathComponent("server.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        output = try FileHandle(forWritingTo: log)
        let child = Process()
        child.executableURL = executable
        child.arguments = ["-L", socket, "server", "nodaemon"]
        var env = environment
        env["ADB_SERVER_SOCKET"] = socket
        env["ADB_USB"] = "0"
        env["ADB_EMU"] = "0"
        env["ADB_MDNS_AUTO_CONNECT"] = "0"
        env.removeValue(forKey: "ADB_TRACE")
        child.environment = env
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = output
        process = child; self.executable = executable
        do {
            try child.run()
            let deadline = Date().addingTimeInterval(5)
            let path = directory.appendingPathComponent("adb.sock").path
            while child.isRunning && !FileManager.default.fileExists(atPath: path) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard child.isRunning, FileManager.default.fileExists(atPath: path) else {
                let detail = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                throw InputError.invalid("Could not start the Wi-Fi connection service. " + String(detail.suffix(2000)))
            }
        } catch {
            stopProcess()
            throw error
        }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        closed = true
        stopProcess()
    }

    private func stopProcess() {
        if let child = process, child.isRunning {
            child.terminate()
            let deadline = Date().addingTimeInterval(1)
            while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        process = nil; executable = nil
        try? output?.close(); output = nil
        try? FileManager.default.removeItem(at: directory)
    }

    deinit { stop() }
}

func wirelessFailureMessage(_ output: String) -> String {
    let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.lowercased().contains("no route to host") || text.lowercased().contains("network is unreachable") {
        return "Cannot reach the phone. Allow this app in System Settings → Privacy & Security → Local Network, keep both devices on the same Wi-Fi, then retry. If the phone’s address changed, refresh the nearby devices.\n\n" + text
    }
    return text
}
