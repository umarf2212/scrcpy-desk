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
