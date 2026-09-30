import AppKit
import SwiftUI

final class DeskModel: ObservableObject {
    @Published var options: Options { didSet { if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data, forKey: "options.v1") } } }
    @Published var devices: [Device] = []
    @Published var selected = ""
    @Published var scanning = false
    @Published var busy = false
    @Published var running = false
    @Published var stopping = false
    @Published var logs = ""
    @Published var status = "Connect your Android to get started"
    @Published var error: String?
    @Published var lastRecording: String?
    private var session: Process?
    private var timer: Timer?
    private var requestedStop = false
    private var recordedPath: String?
    let engineStore: EngineStore
    var root: URL { engineStore.root }
    @Published var engineVersion = EngineStore.bundledVersion
    @Published var updating = false
    @Published var updateStatus = "Check GitHub for the latest stable scrcpy release."
    @Published var showUpdates = false
    @Published var lastUpdateCheck = UserDefaults.standard.object(forKey: "updates.lastCheck") as? Date
    @Published var automaticUpdates = UserDefaults.standard.object(forKey: "updates.automatic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automaticUpdates, forKey: "updates.automatic") }
    }
    var engineSource: String { engineStore.isUpdated ? "Updated" : "Bundled" }
    var optionReference: URL {
        let latest = root.appendingPathComponent("scrcpy-help.txt")
        return FileManager.default.fileExists(atPath: latest.path) ? latest : Bundle.main.resourceURL!.appendingPathComponent("scrcpy-help.txt")
    }
    var selectedDevice: Device? { devices.first { $0.id == selected } }
    var canStart: Bool { selectedDevice?.ready == true && !running && !busy && !updating }
    var command: String { (try? (["scrcpy"] + options.arguments(serial: selected.isEmpty ? "DEVICE" : selected)).map(shellQuote).joined(separator: " ")) ?? "Check your options before starting." }
    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ADB"] = root.appendingPathComponent("adb").path
        env["SCRCPY_SERVER_PATH"] = root.appendingPathComponent("scrcpy-server").path
        env["SCRCPY_ICON_DIR"] = root.path
        env["PATH"] = root.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env.removeValue(forKey: "ANDROID_SERIAL")
        return env
    }
    init(engineStore: EngineStore = EngineStore()) {
        self.engineStore = engineStore
        self.engineVersion = engineStore.version
        options = UserDefaults.standard.data(forKey: "options.v1").flatMap { try? JSONDecoder().decode(Options.self, from: $0) } ?? Options()

    }
    func begin() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh(); self?.checkAutomatically() }
    }
    func checkAutomatically() {
        guard automaticUpdates, !running, !busy, !updating else { return }
        let previous = UserDefaults.standard.object(forKey: "updates.lastAttempt") as? Date ?? .distantPast
        if Date().timeIntervalSince(previous) >= 24 * 60 * 60 { checkAndUpdate() }
    }
    func checkAndUpdate() {
        guard !updating, !running, !busy else { return }
        updating = true
        updateStatus = "Checking the official scrcpy GitHub release…"
        UserDefaults.standard.set(Date(), forKey: "updates.lastAttempt")
        let store = engineStore
        Task { @MainActor in
            defer { updating = false; refresh() }
            do {
                let updater = EngineUpdater()
                let release = try await updater.latest()
                lastUpdateCheck = Date()
                UserDefaults.standard.set(lastUpdateCheck, forKey: "updates.lastCheck")
                guard let asset = try release.updateAsset(current: store.version, arch: store.arch) else {
                    updateStatus = "You’re up to date. scrcpy \(store.version) is installed."
                    return
                }
                updateStatus = "Downloading scrcpy \(release.tag_name)…"
                let archive = try await updater.download(asset)
                defer { try? FileManager.default.removeItem(at: archive) }
                updateStatus = "Verifying and installing scrcpy \(release.tag_name)…"
                let version = try await Task.detached(priority: .userInitiated) { try store.install(archive: archive, release: release) }.value
                engineVersion = version
                updateStatus = "Updated to scrcpy \(version). Ready for your next session."
                append("\n" + updateStatus + "\n")
            } catch {
                updateStatus = "Update failed: " + error.localizedDescription
                append("\n" + updateStatus + "\n")
            }
        }
    }
    func rollbackEngine() {
        guard !running, !busy, !updating, !scanning else { return }
        do {
            try engineStore.rollback()
            engineVersion = engineStore.version
            automaticUpdates = false
            updateStatus = "Restored scrcpy \(engineVersion). Automatic updates are off so this version stays selected."
            append("\n" + updateStatus + "\n")
            refresh()
        } catch { updateStatus = "Could not restore the previous engine: " + error.localizedDescription }
    }
    func append(_ text: String) {
        logs += text
        if logs.count > 120_000 { logs = String(logs.suffix(100_000)) }
    }
    // A bounded worker captures output without blocking the UI or filling a pipe.
    func adb(_ arguments: [String], timeout: Double = 15, completion: @escaping (Int32, String) -> Void) {
        let executable = root.appendingPathComponent("adb"), env = environment
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process(), pipe = Pipe()
            process.executableURL = executable; process.arguments = arguments; process.environment = env
            process.standardOutput = pipe; process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                let hardStop = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 2, execute: hardStop)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit(); watchdog.cancel(); hardStop.cancel()
                let code = process.terminationStatus
                let output = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async { completion(code, output.isEmpty && code != 0 ? "ADB timed out or exited with code \(code)." : output) }
            } catch {
                DispatchQueue.main.async { completion(-1, error.localizedDescription) }
            }
        }
    }
    func refresh() {
        guard !scanning, !busy, !updating else { return }
        scanning = true
        adb(["devices", "-l"]) { [weak self] code, text in
            guard let self else { return }; self.scanning = false
            if code == 0 {
                self.devices = Device.parse(text)
                if !self.devices.contains(where: { $0.id == self.selected }) { self.selected = self.devices.first(where: \.ready)?.id ?? self.devices.first?.id ?? "" }
                if !self.running { self.status = self.devices.isEmpty ? "Connect your Android to get started" : "\(self.devices.filter(\.ready).count) device(s) ready" }
            } else {
                self.devices = []; self.selected = ""
                if !self.running { self.status = "Device scan failed — see Activity" }
                if !self.logs.hasSuffix(text) { self.append(text) }
            }
        }
    }
    func connect(_ endpoint: String, pairCode: String? = nil) {
        guard !busy, !updating, !running else { return }
        do {
            let address = try validateEndpoint(endpoint)
            var args = ["connect", address]
            if let code = pairCode {
                guard code.count == 6, code.allSatisfy(\.isNumber) else { throw InputError.invalid("Enter the six-digit pairing code shown on your phone.") }
                args = ["pair", address, code]
            }
            busy = true
            append(pairCode == nil ? "\nConnecting to \(address)…\n" : "\nPairing with \(address)…\n")
            adb(args, timeout: 30) { [weak self] code, text in
                guard let self else { return }; self.busy = false; self.append(text)
                if code != 0 || text.lowercased().contains("failed") || text.lowercased().contains("cannot") { self.error = text }
                else { self.status = pairCode == nil ? "Connected. Select your device to start." : "Paired. Now connect using the main wireless debugging port." }
                self.refresh()
            }
        } catch { self.error = error.localizedDescription }
    }
    func chooseRecording() {
        let panel = NSSavePanel()
        panel.title = "Save screen recording"; panel.nameFieldStringValue = "Android-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-" )).mkv"
        panel.allowedContentTypes = [.init(filenameExtension: "mkv")!, .mpeg4Movie]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { options.recordPath = url.path; options.recording = true }
    }
    func start() {
        guard canStart else { return }
        do {
            let args = try options.arguments(serial: selected)
            if options.recording {
                let destination = URL(fileURLWithPath: options.recordPath)
                guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else { throw InputError.invalid("The recording folder is not writable. Choose a different location.") }
                if FileManager.default.fileExists(atPath: destination.path) {
                    let alert = NSAlert(); alert.messageText = "Replace existing recording?"; alert.informativeText = destination.lastPathComponent
                    alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Replace")
                    guard alert.runModal() == .alertSecondButtonReturn else { return }
                }
            }
            let process = Process(), pipe = Pipe()
            process.executableURL = root.appendingPathComponent("scrcpy"); process.arguments = args; process.environment = environment
            process.standardOutput = pipe; process.standardError = pipe; process.standardInput = FileHandle.nullDevice
            append("\n▶ " + command + "\n")
            try process.run()
            session = process; running = true; stopping = false; requestedStop = false
            recordedPath = options.recording ? options.recordPath : nil
            status = "Mirroring \(selectedDevice?.name ?? selected)"
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let handle = pipe.fileHandleForReading
                while let data = try? handle.read(upToCount: 4096), !data.isEmpty {
                    let chunk = String(decoding: data, as: UTF8.self)
                    DispatchQueue.main.async { self?.append(chunk) }
                }
                process.waitUntilExit()
                DispatchQueue.main.async {
                    guard let self else { return }
                    let code = process.terminationStatus
                    self.running = false; self.stopping = false; self.session = nil
                    self.append("\nSession ended (\(code)).\n")
                    self.status = self.requestedStop || code == 0 ? "Session ended" : "Session failed — see Activity"
                    if !self.requestedStop && code != 0 { self.error = "scrcpy exited with code \(code). Check Activity for details. Make sure your phone is unlocked and USB debugging is authorized." }
                    if let path = self.recordedPath, FileManager.default.fileExists(atPath: path) { self.lastRecording = path }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        guard let process = session, process.isRunning, !stopping else { return }
        stopping = true; requestedStop = true; status = "Stopping and finalizing recording…"
        process.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            if process.isRunning { self?.append("\nProcess did not stop normally; terminating. A recording may be incomplete.\n"); process.terminate() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
    }
    func exportLog() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "ScrcpyDesk.log"
        if panel.runModal() == .OK, let url = panel.url {
            do { try logs.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: DeskModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.running else { return .terminateNow }
        model.stop()
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            if !model.running { timer.invalidate(); sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
