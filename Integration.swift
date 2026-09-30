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
  model.options.recording = true; model.options.recordPath = recording; model.options.title = "A phone; $(literal)"
  model.start(); pump { !model.running }
  precondition(model.logs.contains("ARG:--window-title=A phone; $(literal)"))
  precondition(model.logs.contains("ARG:--record=\(recording)"))
  precondition(model.lastRecording == recording && FileManager.default.fileExists(atPath: recording))
  try! FileManager.default.removeItem(atPath: recording)
  model.options.recording = false; model.options.extra = "--print-fps"
  model.start(); precondition(model.running); model.stop(); pump({ !model.running }, seconds: 15)
  precondition(!model.stopping)
  model.connect("192.168.1.2:5555"); pump { !model.busy && !model.scanning }
  precondition(model.logs.contains("connected to 192.168.1.2:5555"))
  model.options.extra = "'unclosed"; model.start()
  precondition(!model.running && model.error != nil)
  print("Passed integration: device discovery, launch arguments, recording path, session completion, stop, connect and invalid-input handling.")
 }
}
