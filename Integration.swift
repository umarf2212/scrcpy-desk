import Foundation
import AppKit
@main struct Integration {
 static func pump(_ condition: () -> Bool, seconds: Double = 5) {
  let deadline = Date().addingTimeInterval(seconds)
  while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
  precondition(condition(), "Async operation timed out")
 }
 static func main() {
  let model = DeskModel(engineStore: EngineStore(base: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
  model.options = Options()
  model.refresh(); pump { !model.scanning }
  precondition(model.devices.count == 2 && model.selected == "TEST_SERIAL" && model.canStart)
  let recording = NSTemporaryDirectory() + "ScrcpyDesk test recording \(UUID().uuidString).mkv"
  model.options.setDesktopEnabled(true)
  model.options.recording = true; model.options.recordPath = recording; model.options.title = "A phone; $(literal)"
  model.start(); pump { !model.running }
  precondition(model.logs.contains("SERVER_SOCKET:shared"), "USB session uses the shared server")
  precondition(model.logs.contains("ARG:--window-title=A phone; $(literal)"))
  precondition(model.logs.contains("ARG:--new-display=1920x1080/160"), "launch virtual display from option")
  model.options.setDesktopEnabled(false)
  precondition(model.logs.contains("ARG:--record=\(recording)"))
  precondition(model.lastRecording == recording && FileManager.default.fileExists(atPath: recording))
  try! FileManager.default.removeItem(atPath: recording)
  model.options.recording = false; model.options.extra = "--print-fps"
  model.start(); precondition(model.running); model.stop(); pump({ !model.running }, seconds: 15)
  precondition(!model.stopping)
  var sharedResult: (Int32, String)?
  model.adb(["connect", "192.168.1.4:43787"]) { sharedResult = ($0, $1) }
  pump { sharedResult != nil }
  precondition(sharedResult!.0 != 0 && sharedResult!.1.contains("No route to host"), "reproduce stale shared-server failure")
  model.connect("192.168.1.2:5555"); pump { !model.busy && !model.scanning }
  precondition(model.logs.contains("connected to 192.168.1.2:5555"), "Wi-Fi connect failed: \(model.error ?? model.logs)")
  model.scanWireless(); pump { !model.wirelessScanning && !model.busy && !model.scanning }
  precondition(model.wirelessServices.count == 2, "unpaired phone must be discoverable")
  precondition(model.wirelessFailures["192.168.1.4:43787"]?.contains("authenticate") == true, "show automatic connection failures beside the device")
  precondition(model.error == nil, "automatic authentication failure must not show a modal error")
  let pairing = model.wirelessServices.first { $0.kind == .pairing }!
  let connection = model.wirelessServices.first { $0.kind == .connection }!
  precondition(pairing.port != connection.port)
  let attemptsURL = model.root.appendingPathComponent("adb.connections")
  let attemptsBefore = try! String(contentsOf: attemptsURL, encoding: .utf8)
  model.scanWireless(); pump { !model.wirelessScanning && !model.busy }
  precondition(try! String(contentsOf: attemptsURL, encoding: .utf8) == attemptsBefore, "do not repeatedly connect to unpaired phones")
  model.connect(pairing.endpoint, pairCode: "123456")
  pump { !model.busy && !model.wirelessScanning && !model.scanning && model.devices.contains { $0.id == connection.endpoint } }
  precondition(model.logs.contains("Successfully paired to 192.168.1.4:37123"))
  precondition(model.logs.contains("connected to 192.168.1.4:43787"), "pairing must automatically use the connection port")
  precondition(model.wirelessConnected(connection))
  precondition(model.wirelessFailures[connection.endpoint] == nil, "clear the connection diagnostic on success")
  precondition(model.devices.contains { $0.id == "TEST_SERIAL" }, "Wi-Fi recovery preserves shared USB devices")
  let serverStartsURL = model.root.appendingPathComponent("adb.servers")
  let serverStarts = try! String(contentsOf: serverStartsURL, encoding: .utf8).split(separator: "\n")
  precondition(serverStarts.count == 1, "reuse one foreground Wi-Fi server across scans and pairing")
  let socket = String(serverStarts[0])
  precondition(socket.hasPrefix("localfilesystem:/tmp/scrcpy-wifi-"), "private local socket")
  model.selected = connection.endpoint
  model.options.extra = ""
  model.logs = ""
  model.start(); pump { !model.running }
  precondition(model.logs.contains("SERVER_SOCKET:" + socket), "wireless scrcpy session uses the private server")
  model.shutdown()
  precondition(!FileManager.default.fileExists(atPath: String(socket.dropFirst("localfilesystem:".count))), "remove private socket on shutdown")
  precondition(FileManager.default.fileExists(atPath: model.root.appendingPathComponent("adb.connected").path), "shutdown must not kill shared ADB")
  model.options.extra = "'unclosed"; model.start()
  precondition(!model.running && model.error != nil)
  print("Passed integration: device discovery, launch arguments, recording path, session completion, stop, connect, unpaired Wi-Fi discovery, automatic connection after pairing, retry suppression, stale-server isolation, USB/Wi-Fi routing, owned-server cleanup and invalid-input handling.")
 }
}
