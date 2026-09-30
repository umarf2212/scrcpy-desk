import SwiftUI
import AppKit
import UniformTypeIdentifiers

let mint = Color(red: 0.40, green: 0.88, blue: 0.73)
let canvas = Color(red: 0.065, green: 0.078, blue: 0.095)
let panelColor = Color(red: 0.105, green: 0.122, blue: 0.145)

@main
struct ScrcpyDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = DeskModel()
    var body: some Scene {
        WindowGroup("Scrcpy Desk") {
            DeskView(model: model)
                .preferredColorScheme(.dark)
                .onAppear { if delegate.model == nil { delegate.model = model; model.begin() }; NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1050, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for scrcpy Updates…") { model.showUpdates = true; model.checkAndUpdate() }.disabled(model.updating || model.running || model.busy)
            }
            CommandMenu("Session") {
                Button("Start Mirroring") { model.start() }.keyboardShortcut(.return, modifiers: .command).disabled(!model.canStart)
                Button("Stop Mirroring") { model.stop() }.keyboardShortcut(".", modifiers: .command).disabled(!model.running)
                Divider()
                Button("Refresh Devices") { model.refresh() }.keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

struct DeskView: View {
    @ObservedObject var model: DeskModel
    @State private var tab = "Mirror"
    @State private var wireless = false
    let tabs = ["Mirror", "Audio", "Control", "Advanced", "Activity", "Updates"]
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 236)
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 30).padding(.top, 34).padding(.bottom, 24)
                HStack(spacing: 22) {
                    ForEach(tabs, id: \.self) { name in
                        Button { tab = name } label: {
                            VStack(spacing: 12) {
                                Text(name).font(.system(size: 13, weight: tab == name ? .semibold : .regular)).foregroundStyle(tab == name ? mint : .secondary)
                                Capsule().fill(tab == name ? mint : .clear).frame(height: 2)
                            }.fixedSize(horizontal: true, vertical: false)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(.horizontal, 30)
                Divider().opacity(0.35)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if tab == "Mirror" { mirrorPanel }
                        if tab == "Audio" { audioPanel }
                        if tab == "Control" { controlPanel }
                        if tab == "Advanced" { advancedPanel }
                        if tab == "Activity" { activityPanel }
                        if tab == "Updates" { updatesPanel }
                    }.padding(30).disabled(model.running && tab != "Activity")
                }
                footer
            }
        }
        .background(canvas)
        .frame(minWidth: 940, minHeight: 720)
        .tint(mint)
        .onChange(of: model.showUpdates) { value in if value { tab = "Updates"; model.showUpdates = false } }
        .sheet(isPresented: $wireless) { WirelessView(model: model) }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("View Activity") { tab = "Activity"; model.error = nil }
            Button("Dismiss", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle").font(.system(size: 24, weight: .medium)).foregroundStyle(mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("scrcpy desk").font(.system(size: 18, weight: .semibold))
                    Text("ANDROID, ON YOUR MAC").font(.system(size: 8, weight: .bold)).tracking(1.6).foregroundStyle(.secondary)
                }
            }.padding(.top, 38).padding(.bottom, 16)
            HStack {
                Text("DEVICES").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Spacer()
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").rotationEffect(.degrees(model.scanning ? 180 : 0)) }.buttonStyle(.plain).help("Refresh devices").disabled(model.scanning)
            }
            if model.devices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "cable.connector").font(.system(size: 29)).foregroundStyle(.secondary)
                    Text("Waiting for a device").font(.system(size: 13, weight: .medium))
                    Text("Connect with USB, or pair your phone over Wi-Fi.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.devices) { device in
                            Button { model.selected = device.id } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: device.wireless ? "wifi" : "iphone").font(.system(size: 19)).foregroundStyle(device.ready ? mint : .orange)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                        Text(device.ready ? (device.wireless ? "Wi-Fi · Ready" : "USB · Ready") : device.state.capitalized).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if model.selected == device.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(mint) }
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(model.selected == device.id ? mint.opacity(0.09) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(model.running).help(device.id)
                        }
                    }
                }.frame(maxHeight: 220)
            }
            Button { wireless = true } label: { Label("Connect over Wi-Fi", systemImage: "wifi").font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.bordered).disabled(model.running || model.updating)
            if let device = model.selectedDevice, !device.ready {
                Text(device.state == "unauthorized" ? "Unlock your phone and accept the USB debugging prompt, then refresh." : "Reconnect your phone and check that USB debugging is enabled.").font(.system(size: 12)).foregroundStyle(.orange).lineSpacing(4)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Label("FIRST CONNECTION", systemImage: "info.circle").font(.system(size: 9, weight: .bold)).tracking(1)
                Text("1  Enable Developer options\n2  Turn on USB debugging\n3  Connect & allow this Mac").font(.system(size: 11)).lineSpacing(7)
            }.foregroundStyle(.secondary)
            Divider().opacity(0.4)
            HStack {
                Circle().fill(mint).frame(width: 5, height: 5)
                Text("scrcpy \(model.engineVersion) · \(model.engineSource)").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Link(destination: URL(string: "https://github.com/Genymobile/scrcpy")!) { Image(systemName: "arrow.up.right").font(.system(size: 10)) }
            }
        }.padding(.horizontal, 20).padding(.bottom, 22).background(Color.black.opacity(0.16))
    }
    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tab == "Activity" ? "Behind the screen." : "Your phone. More room.").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(tab == "Activity" ? "Session output and connection diagnostics." : "Mirror, control, and record your Android screen.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) { Circle().fill(model.running ? mint : Color.gray).frame(width: 6, height: 6); Text(model.running ? "LIVE" : "STANDBY").font(.system(size: 9, weight: .bold)).tracking(1) }.padding(.horizontal, 10).padding(.vertical, 7).background(Color.white.opacity(0.05), in: Capsule())
        }
    }
    var mirrorPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Make it feel right", subtitle: "Choose a starting point, then fine-tune below.")
            HStack(spacing: 10) {
                preset("Responsive", icon: "bolt", detail: "720-class · 60 fps", caption: "Lighter & quicker")
                preset("Balanced", icon: "slider.horizontal.3", detail: "1080-class · 60 fps", caption: "The everyday choice")
                preset("Crisp", icon: "sparkles", detail: "Native size · H.265", caption: "Every little detail")
            }
            card("VIDEO", icon: "display") {
                HStack(spacing: 24) {
                    pick("Maximum size", value: $model.options.size, choices: [("1280", "1280 px"), ("1920", "1920 px"), ("2560", "2560 px"), ("0", "Native")])
                    pick("Frame rate", value: $model.options.fps, choices: [("30", "30 fps"), ("60", "60 fps"), ("90", "90 fps"), ("120", "120 fps"), ("0", "Unlimited")])
                    pick("Codec", value: $model.options.codec, choices: [("h264", "H.264"), ("h265", "H.265"), ("av1", "AV1")])
                }
                HStack { Text("Video bitrate").font(.system(size: 12)); Spacer(); TextField("8", text: $model.options.bitrate).textFieldStyle(.roundedBorder).frame(width: 70); Text("Mbps").font(.system(size: 11)).foregroundStyle(.secondary) }
                Text("Maximum size limits the longer edge. H.265 and AV1 need device encoder support.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            card("WINDOW", icon: "macwindow") {
                HStack { Toggle("Always on top", isOn: $model.options.onTop); Spacer(); Toggle("Start fullscreen", isOn: $model.options.fullscreen) }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
            }
            card("RECORDING", icon: "record.circle") {
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text("Save the session").font(.system(size: 13, weight: .medium)); Text("Recording begins when you start mirroring.").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Spacer(); Toggle("Record session", isOn: $model.options.recording).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if model.options.recording {
                    HStack { Text(model.options.recordPath.isEmpty ? "Choose an MP4 or MKV file" : model.options.recordPath).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle); Spacer(); Button("Choose File…") { model.chooseRecording() } }
                }
            }
        }
    }
    func preset(_ name: String, icon: String, detail: String, caption: String) -> some View {
        let selected = model.options.presetName == name
        return Button { model.options.preset(name) } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack { Image(systemName: icon).font(.system(size: 17)).foregroundStyle(selected ? mint : .secondary); Spacer(); if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(mint) } }
                Text(name).font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 4) { Text(detail).font(.system(size: 10, weight: .medium)); Text(caption).font(.system(size: 10)).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(selected ? mint.opacity(0.07) : panelColor, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? mint.opacity(0.6) : Color.white.opacity(0.07), lineWidth: 1))
        }.buttonStyle(.plain)
    }
    var audioPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Bring the sound along", subtitle: "Audio forwarding requires Android 11 or later.")
            card("AUDIO", icon: "speaker.wave.2") {
                toggleRow("Forward audio", detail: "Play phone audio on your Mac.", value: $model.options.audio)
                Divider()
                HStack(spacing: 24) {
                    pick("Source", value: $model.options.audioSource, choices: [("output", "Device output"), ("playback", "App playback"), ("mic", "Microphone")])
                    pick("Audio codec", value: $model.options.audioCodec, choices: [("opus", "Opus"), ("aac", "AAC"), ("flac", "FLAC"), ("raw", "Raw")])
                }.disabled(!model.options.audio)
                Text("Device output mutes playback on the phone. App playback requires Android 13+ and apps may opt out. Unlock Android 11 devices before starting audio capture.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }
    }
    var controlPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("A little more hands-on", subtitle: "Choose how your Mac interacts with your phone.")
            card("INPUT", icon: "keyboard") {
                toggleRow("Control the device", detail: "Use your Mac keyboard and mouse.", value: $model.options.control)
                HStack(spacing: 24) {
                    pick("Keyboard", value: $model.options.keyboard, choices: [("sdk", "Standard"), ("uhid", "Physical (UHID)"), ("disabled", "Disabled")])
                    pick("Mouse", value: $model.options.mouse, choices: [("sdk", "Standard"), ("uhid", "Physical (UHID)"), ("disabled", "Disabled")])
                }.disabled(!model.options.control)
                Text("UHID mouse captures the pointer. Press Option or Command to release it.").font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                toggleRow("Sync clipboard", detail: "Share clipboard text between your Mac and Android.", value: $model.options.clipboard)
            }
            card("PHONE", icon: "iphone") {
                toggleRow("Turn phone screen off", detail: "Keep mirroring while the phone screen is dark.", value: $model.options.screenOff)
                toggleRow("Stay awake", detail: "Prevent sleep while the phone is plugged in.", value: $model.options.awake)
                toggleRow("Show touches", detail: "Display physical touches on the phone screen.", value: $model.options.touches)
            }.disabled(!model.options.control)
            card("HANDY SHORTCUTS", icon: "command") {
                Text("In the mirror window:  ⌘ F  Fullscreen     ⌘ H  Home     ⌘ B  Back\n⌘ O  Phone screen off     ⌘ ⇧ O  Phone screen on").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(10)
            }
        }
    }
    var advancedPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("For the fine-tuners", subtitle: "More control, with the full scrcpy CLI within reach.")
            card("CAPTURE & WINDOW", icon: "crop.rotate") {
                HStack(spacing: 24) {
                    pick("Capture rotation", value: $model.options.orientation, choices: [("0", "Automatic"), ("@", "Lock current"), ("@0", "Lock 0°"), ("@90", "Lock 90°"), ("@180", "Lock 180°"), ("@270", "Lock 270°")])
                    VStack(alignment: .leading, spacing: 8) { Text("Window title").font(.system(size: 11)).foregroundStyle(.secondary); TextField("Device name", text: $model.options.title).textFieldStyle(.roundedBorder) }
                }
                TextField("Crop: width:height:x:y (optional)", text: $model.options.crop).textFieldStyle(.roundedBorder)
                Toggle("Borderless window", isOn: $model.options.borderless).font(.system(size: 12))
            }
            card("ADDITIONAL ARGUMENTS", icon: "terminal") {
                TextField("e.g. --video-buffer=50 --print-fps", text: $model.options.extra).textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                Text("Supports quoted values. Arguments are passed directly to scrcpy; shell commands are not executed. Avoid duplicating options already set above.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                HStack {
                    Button("Full option reference") { NSWorkspace.shared.open(model.optionReference) }
                    Spacer()
                    Button("Reset options") { model.options = Options() }
                }
            }
            card("COMMAND PREVIEW", icon: "chevron.left.forwardslash.chevron.right") {
                Text(model.command).font(.system(size: 11, design: .monospaced)).foregroundStyle(mint.opacity(0.85)).textSelection(.enabled).lineSpacing(5)
                Button("Copy Command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.command, forType: .string) }
            }
        }
    }
    var updatesPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Keep the engine fresh", subtitle: "Stable releases from Genymobile’s official scrcpy repository.")
            card("SCRCPY ENGINE", icon: "arrow.down.circle") {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("scrcpy \(model.engineVersion)").font(.system(size: 23, weight: .semibold, design: .rounded))
                        Text("\(model.engineSource) · \(EngineStore.architecture == "arm64" ? "Apple Silicon" : "Intel")").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.updating { ProgressView().controlSize(.small) }
                    Button(model.updating ? "Updating…" : "Check & Update") { model.checkAndUpdate() }
                        .disabled(model.updating || model.running || model.busy)
                }
                Text(model.updateStatus).font(.system(size: 12)).foregroundStyle(mint).textSelection(.enabled).lineSpacing(4)
                if let date = model.lastUpdateCheck {
                    Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            card("AUTOMATIC UPDATES", icon: "arrow.triangle.2.circlepath") {
                toggleRow("Check and install daily", detail: "While this app is open and no mirror session is running.", value: $model.automaticUpdates)
                Text("Downloads the matching Mac release, verifies its SHA-256 digest, and checks that scrcpy and ADB run before switching. Active mirror sessions are never interrupted.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
            card("RECOVERY", icon: "clock.arrow.circlepath") {
                Text("The bundled scrcpy 4.1 stays inside the app. Updates are stored separately in your Application Support folder, with the previous engine retained.").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                if model.engineStore.isUpdated {
                    Button("Restore scrcpy \(model.engineStore.rollbackVersion)") { model.rollbackEngine() }
                        .disabled(model.updating || model.running || model.busy || model.scanning)
                }
                Link("View official releases ↗", destination: URL(string: "https://github.com/Genymobile/scrcpy/releases")!).font(.system(size: 12))
            }
            Text("This updates scrcpy and its bundled ADB, not the Scrcpy Desk interface. No admin password or app restart is required.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    var activityPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { sectionTitle("Session activity", subtitle: "Recent output from scrcpy and ADB."); Spacer(); Button("Export…") { model.exportLog() }; Button("Clear") { model.logs = "" } }
            ScrollView([.vertical, .horizontal]) {
                Text(model.logs.isEmpty ? "No activity yet. Connect a device and start mirroring." : model.logs).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.white.opacity(0.75)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(16)
            }.frame(minHeight: 340, maxHeight: 430).background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            if let recording = model.lastRecording { Button("Show Last Recording in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: recording)]) } }
            Text("Logs may include device identifiers and network addresses. Review them before sharing.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.status).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    Text(model.running ? "Options apply to your next session." : "\(model.options.presetName) · \(model.options.audio ? "Audio on" : "Audio off") · \(model.options.recording ? "Recording on" : "Recording off")").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { if model.running { model.stop() } else { model.start() } } label: {
                    Label(model.stopping ? "Stopping…" : model.running ? "Stop Mirroring" : "Start Mirroring", systemImage: model.running ? "stop.fill" : "play.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.black.opacity(0.9)).padding(.horizontal, 18).padding(.vertical, 12).background(model.running ? Color.orange : mint, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).disabled(model.stopping || (!model.running && !model.canStart)).opacity(model.canStart || model.running ? 1 : 0.4).keyboardShortcut(.return, modifiers: .command)
            }.padding(.horizontal, 30).padding(.vertical, 19)
        }.background(panelColor.opacity(0.35))
    }
    func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 17, weight: .semibold)); Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
    }
    func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(panelColor, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05)))
    }
    func pick(_ label: String, value: Binding<String>, choices: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Picker(label, selection: value) { ForEach(choices, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().frame(maxWidth: .infinity)
        }
    }
    func toggleRow(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 13, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            Spacer(); Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct WirelessView: View {
    @ObservedObject var model: DeskModel
    @Environment(\.dismiss) private var dismiss
    @State private var pairingAddress = ""
    @State private var code = ""
    @State private var connectAddress = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Image(systemName: "wifi").font(.title2).foregroundStyle(mint); Text("Connect over Wi-Fi").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Keep your Mac and phone on the same network. On Android 11+, open Developer options → Wireless debugging.").font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Pair once").font(.headline)
                    Text("Tap “Pair device with pairing code” on your phone. Use the address and port inside that dialog.").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("Pairing IP:port", text: $pairingAddress)
                    HStack { SecureField("Six-digit pairing code", text: $code); Button("Pair") { model.connect(pairingAddress, pairCode: code); code = "" }.disabled(model.busy || code.isEmpty) }
                }.padding(10)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("2. Connect").font(.headline)
                    Text("Use the IP address and port on the main Wireless debugging page. The connection port is different from the pairing port.").font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack { TextField("Connection IP:port", text: $connectAddress); Button("Connect") { model.connect(connectAddress) }.disabled(model.busy || connectAddress.isEmpty) }
                }.padding(10)
            }
            if model.busy { ProgressView().controlSize(.small) }
            Text(model.status).font(.system(size: 12)).foregroundStyle(mint)
            ScrollView { Text(String(model.logs.suffix(1800))).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90)
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 520).background(canvas).preferredColorScheme(.dark)
    }
}
