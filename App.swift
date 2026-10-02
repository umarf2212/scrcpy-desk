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
        .defaultSize(width: 980, height: 760)
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
    let tabs = [("Mirror", "display"), ("Audio", "speaker.wave.2"), ("Control", "keyboard"), ("Advanced", "slider.horizontal.3"), ("Activity", "terminal"), ("Updates", "arrow.down.circle")]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 184)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                deviceBar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch tab {
                        case "Audio": audioPanel
                        case "Control": controlPanel
                        case "Advanced": advancedPanel
                        case "Activity": activityPanel
                        case "Updates": updatesPanel
                        default: mirrorPanel
                        }
                    }
                    .frame(maxWidth: 840, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(model.running && tab != "Activity")
                }.id(tab)
                footer
            }
        }
        .background(canvas)
        .frame(minWidth: 840, minHeight: 640)
        .tint(mint)
        .onChange(of: model.showUpdates) { value in if value { tab = "Updates"; model.showUpdates = false } }
        .sheet(isPresented: $wireless) { WirelessView(model: model) }
        .alert("Unable to complete action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("View Activity") { tab = "Activity"; model.error = nil }
            Button("Dismiss", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scrcpy Desk").font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 12).padding(.top, 48).padding(.bottom, 28)
            ForEach(tabs.prefix(4), id: \.0) { name, icon in navigationItem(name, icon: icon) }
            Divider().padding(.horizontal, 12).padding(.vertical, 16)
            ForEach(tabs.suffix(2), id: \.0) { name, icon in navigationItem(name, icon: icon) }
            Spacer(minLength: 24)
            Link(destination: URL(string: "https://github.com/Genymobile/scrcpy")!) {
                HStack {
                    Text("scrcpy \(model.engineVersion)").font(.system(size: 11))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 10))
                }.foregroundStyle(.secondary)
            }.help("Open scrcpy on GitHub").padding(12)
        }.padding(.horizontal, 12).padding(.bottom, 12).background(Color.black.opacity(0.14))
    }

    func navigationItem(_ name: String, icon: String) -> some View {
        Button { tab = name } label: {
            Label(name, systemImage: icon)
                .font(.system(size: 13, weight: tab == name ? .semibold : .regular))
                .foregroundStyle(tab == name ? Color.white : Color.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(tab == name ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.bottom, 4)
            .accessibilityAddTraits(tab == name ? .isSelected : [])
    }

    var header: some View {
        HStack {
            Text(tab).font(.system(size: 22, weight: .semibold))
            Spacer()
            if model.running {
                Label(model.stopping ? "Stopping…" : "Mirroring", systemImage: "record.circle")
                    .font(.system(size: 12)).foregroundStyle(mint)
            }
        }.padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 20)
    }

    var deviceBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if model.devices.isEmpty {
                    Label("No device connected", systemImage: "cable.connector")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    Picker("Device", selection: $model.selected) {
                        ForEach(model.devices) { device in
                            Text("\(device.name) · \(device.ready ? (device.wireless ? "Wi-Fi" : "USB") : device.state.capitalized)").tag(device.id)
                        }
                    }.labelsHidden().frame(maxWidth: 360).disabled(model.running)
                        .help(model.selectedDevice?.id ?? "Select a device")
                }
                Spacer(minLength: 8)
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh devices").help("Refresh devices (⌘R)")
                    .disabled(model.scanning || model.running)
                Button { wireless = true } label: { Label("Connect over Wi-Fi", systemImage: "wifi") }
                    .disabled(model.running || model.updating)
            }.controlSize(.regular)
            if model.devices.isEmpty {
                hint(model.wirelessServices.isEmpty
                     ? "Enable USB debugging, connect your phone, then accept the authorization prompt."
                     : "A wireless device is available. Open Connect over Wi-Fi to pair it.")
            } else if let device = model.selectedDevice, !device.ready {
                hint(device.state == "unauthorized"
                     ? "Unlock your phone and accept the debugging prompt, then refresh."
                     : "Reconnect your phone and check that USB debugging is enabled.")
                    .foregroundStyle(.orange)
            }
        }.padding(.horizontal, 28).padding(.bottom, 20)
    }

    var mirrorPanel: some View {
        VStack(spacing: 0) {
            settingsSection("Quality") {
                Picker("Quality preset", selection: Binding(
                    get: { model.options.presetName },
                    set: { if $0 != "Custom" { model.options.preset($0) } }
                )) {
                    Text("Responsive").tag("Responsive")
                    Text("Balanced").tag("Balanced")
                    Text("Crisp").tag("Crisp")
                    if model.options.presetName == "Custom" { Text("Custom").tag("Custom") }
                }.labelsHidden().pickerStyle(.segmented)
            }
            settingsSection("Video") {
                HStack(alignment: .top, spacing: 16) {
                    pick("Maximum size", value: $model.options.size, choices: [("1280", "1280 px"), ("1920", "1920 px"), ("2560", "2560 px"), ("0", "Native")])
                    pick("Frame rate", value: $model.options.fps, choices: [("30", "30 fps"), ("60", "60 fps"), ("90", "90 fps"), ("120", "120 fps"), ("0", "Unlimited")])
                    pick("Codec", value: $model.options.codec, choices: [("h264", "H.264"), ("h265", "H.265"), ("av1", "AV1")])
                }
                HStack(spacing: 8) {
                    Text("Bitrate").font(.system(size: 13))
                    Spacer()
                    TextField("8", text: $model.options.bitrate).accessibilityLabel("Video bitrate")
                        .textFieldStyle(.roundedBorder).frame(width: 72)
                    Text("Mbps").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                hint("Maximum size limits the longer edge. H.265 and AV1 require a supported device encoder.")
            }
            settingsSection("Display") {
                toggleRow("Desktop mode / virtual display", value: Binding(
                    get: { model.options.desktopSettings.enabled },
                    set: { model.options.setDesktopEnabled($0) }
                ))
                if model.options.desktopSettings.enabled {
                    HStack(alignment: .top, spacing: 16) {
                        pick("Resolution", value: $model.options.desktopSettings.resolution, choices: [("1920x1080", "1920 × 1080"), ("2560x1440", "2560 × 1440"), ("3840x2160", "3840 × 2160")])
                        pick("Density", value: $model.options.desktopSettings.dpi, choices: [("120", "120 dpi"), ("160", "160 dpi"), ("240", "240 dpi"), ("320", "320 dpi")])
                    }
                    hint("The phone determines the desktop interface. Lower density fits more on screen. The virtual display closes with the session.")
                }
            }
            settingsSection("Window") {
                toggleRow("Always on top", value: $model.options.onTop)
                toggleRow("Start fullscreen", value: $model.options.fullscreen)
            }
            settingsSection("Recording", last: true) {
                toggleRow("Record session", value: $model.options.recording)
                if model.options.recording {
                    HStack(spacing: 12) {
                        Text(model.options.recordPath.isEmpty ? "No file selected" : URL(fileURLWithPath: model.options.recordPath).lastPathComponent)
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            .help(model.options.recordPath)
                        Spacer(minLength: 0)
                        Button("Choose File…") { model.chooseRecording() }
                    }
                    hint("Recording starts with mirroring. Choose MP4 or MKV; MKV supports more codecs.")
                }
            }
        }
    }

    var audioPanel: some View {
        VStack(spacing: 0) {
            settingsSection("Forwarding") {
                toggleRow("Forward audio", value: $model.options.audio)
                hint("Requires Android 11 or later. Unlock Android 11 devices before starting capture.")
            }
            settingsSection("Capture", last: true) {
                HStack(alignment: .top, spacing: 16) {
                    pick("Source", value: $model.options.audioSource, choices: [("output", "Device output"), ("playback", "App playback"), ("mic", "Microphone")])
                    pick("Codec", value: $model.options.audioCodec, choices: [("opus", "Opus"), ("aac", "AAC"), ("flac", "FLAC"), ("raw", "Raw")])
                }.disabled(!model.options.audio)
                hint("Device output mutes the phone. App playback requires Android 13+; apps can block capture.")
            }
        }
    }

    var controlPanel: some View {
        VStack(spacing: 0) {
            settingsSection("Input") {
                toggleRow("Control device", value: $model.options.control)
                HStack(alignment: .top, spacing: 16) {
                    pick("Keyboard", value: $model.options.keyboard, choices: [("sdk", "Standard"), ("uhid", "Physical (UHID)"), ("disabled", "Disabled")])
                    pick("Mouse", value: $model.options.mouse, choices: [("sdk", "Standard"), ("uhid", "Physical (UHID)"), ("disabled", "Disabled")])
                }.disabled(!model.options.control)
                hint("UHID captures the pointer. Press Option or Command to release it.")
                toggleRow("Sync clipboard", value: $model.options.clipboard)
            }
            settingsSection("Phone") {
                toggleRow("Turn screen off", detail: "Mirroring continues while the phone screen is off.", value: $model.options.screenOff)
                toggleRow("Stay awake", detail: "Prevents sleep while connected to power.", value: $model.options.awake)
                toggleRow("Show touches", value: $model.options.touches)
            }.disabled(!model.options.control)
            settingsSection("Shortcuts", last: true) {
                shortcut("Fullscreen", keys: "⌘ F")
                shortcut("Home", keys: "⌘ H")
                shortcut("Back", keys: "⌘ B")
                shortcut("Phone screen off", keys: "⌘ O")
                shortcut("Phone screen on", keys: "⌘ ⇧ O")
                hint("Use these shortcuts in the mirror window.")
            }
        }
    }

    var advancedPanel: some View {
        VStack(spacing: 0) {
            settingsSection("Capture") {
                pick("Rotation", value: $model.options.orientation, choices: [("0", "Automatic"), ("@", "Lock current"), ("@0", "Lock 0°"), ("@90", "Lock 90°"), ("@180", "Lock 180°"), ("@270", "Lock 270°")])
                field("Crop", placeholder: "width:height:x:y", text: $model.options.crop)
            }
            settingsSection("Window") {
                field("Title", placeholder: "Device name", text: $model.options.title)
                toggleRow("Borderless window", value: $model.options.borderless)
            }
            settingsSection("Arguments") {
                field("Additional arguments", placeholder: "--video-buffer=50 --print-fps", text: $model.options.extra, monospaced: true)
                hint("Quoted values are supported. Avoid repeating options set in the interface.")
                HStack {
                    Button("Option Reference") { NSWorkspace.shared.open(model.optionReference) }
                    Spacer()
                    Button("Reset Options") { model.options = Options() }
                }
            }
            settingsSection("Command", last: true) {
                Text(model.command).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(panelColor, in: RoundedRectangle(cornerRadius: 6))
                Button("Copy Command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.command, forType: .string) }
            }
        }
    }

    var updatesPanel: some View {
        VStack(spacing: 0) {
            settingsSection("Engine") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("scrcpy \(model.engineVersion)").font(.system(size: 17, weight: .semibold))
                        hint("\(model.engineSource) · \(EngineStore.architecture == "arm64" ? "Apple Silicon" : "Intel")")
                    }
                    Spacer()
                    if model.updating { ProgressView().controlSize(.small) }
                    Button(model.updating ? "Updating…" : "Check & Update") { model.checkAndUpdate() }
                        .disabled(model.updating || model.running || model.busy)
                }
                Text(model.updateStatus).font(.system(size: 12)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = model.lastUpdateCheck { hint("Last checked \(date.formatted(date: .abbreviated, time: .shortened))") }
            }
            settingsSection("Automatic") {
                toggleRow("Check and install daily", value: $model.automaticUpdates)
                hint("Checks while the app is open and idle. Downloads are verified before installation.")
            }
            settingsSection("Recovery", last: true) {
                hint("Updates retain the previous engine. Bundled scrcpy 4.1 is always available for rollback.")
                if model.engineStore.isUpdated {
                    Button("Restore scrcpy \(model.engineStore.rollbackVersion)") { model.rollbackEngine() }
                        .disabled(model.updating || model.running || model.busy || model.scanning)
                }
                Link("Official Releases", destination: URL(string: "https://github.com/Genymobile/scrcpy/releases")!)
                hint("Updates apply to scrcpy and ADB. The Scrcpy Desk interface is updated by downloading a new app release.")
            }
        }
    }

    var activityPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Session output").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Export…") { model.exportLog() }
                Button("Clear") { model.logs = "" }.disabled(model.logs.isEmpty)
            }
            GeometryReader { geometry in
                ScrollView([.vertical, .horizontal]) {
                    Text(model.logs.isEmpty ? "No session output." : model.logs)
                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(minWidth: max(0, geometry.size.width - 32), minHeight: max(0, geometry.size.height - 32), alignment: .topLeading)
                        .padding(16)
                }
            }.frame(height: 360).background(panelColor, in: RoundedRectangle(cornerRadius: 6))
            if let recording = model.lastRecording { Button("Show Last Recording in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: recording)]) } }
            hint("Logs can contain device identifiers, network addresses, and paths. Review before sharing.")
        }
    }

    var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.running ? model.status : (model.canStart ? "Ready to mirror" : model.busy ? "Connecting…" : model.updating ? "Updating engine…" : "Connect a device to start"))
                        .font(.system(size: 12, weight: .medium)).lineLimit(2)
                    if model.running { hint("Stop the session to change options.") }
                    else { hint("\(model.options.desktopSettings.enabled ? "Virtual display" : "Phone screen") · \(model.options.audio ? "Audio on" : "Audio off")\(model.options.recording ? " · Recording on" : "")") }
                }
                Spacer(minLength: 0)
                Button { if model.running { model.stop() } else { model.start() } } label: {
                    Label(model.stopping ? "Stopping…" : model.running ? "Stop Mirroring" : "Start Mirroring", systemImage: model.running ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 6)
                }.buttonStyle(.borderedProminent).tint(model.running ? .orange : mint)
                    .disabled(model.stopping || (!model.running && !model.canStart))
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(model.running ? "Stop mirroring" : "Start mirroring (⌘Return)")
            }.padding(.horizontal, 28).padding(.vertical, 16)
        }.background(panelColor.opacity(0.4))
    }

    func settingsSection<Content: View>(_ title: String, last: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .frame(width: 88, alignment: .leading).padding(.top, 3)
                VStack(alignment: .leading, spacing: 12, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 20)
            if !last { Divider() }
        }
    }

    func pick(_ label: String, value: Binding<String>, choices: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Picker(label, selection: value) { ForEach(choices, id: \.0) { Text($0.1).tag($0.0) } }
                .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    func toggleRow(_ title: String, detail: String? = nil, value: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                if let detail { hint(detail) }
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    func field(_ title: String, placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: monospaced ? .monospaced : .default)).accessibilityLabel(title)
        }
    }

    func shortcut(_ title: String, keys: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Text(keys).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct WirelessView: View {
    @ObservedObject var model: DeskModel
    @Environment(\.dismiss) private var dismiss
    @State private var pairingAddress = ""
    @State private var code = ""
    @State private var connectAddress = ""
    @State private var manualConnection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Connect over Wi-Fi").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    instruction("Connect both devices to the same Wi-Fi. On your phone, enable Developer options → Wireless debugging.")
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Nearby devices").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if model.wirelessScanning { ProgressView().controlSize(.small) }
                            Button("Refresh") { model.scanWireless() }.disabled(model.wirelessScanning || model.busy)
                        }
                        if model.wirelessServices.isEmpty { instruction(model.wirelessStatus) }
                        ForEach(model.wirelessServices) { service in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(service.name).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(service.endpoint).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                        instruction(service.kind == .pairing ? "Pairing service" : model.wirelessConnected(service) ? "Connected" : "Connection service")
                                    }
                                    Spacer(minLength: 0)
                                    if service.kind == .pairing {
                                        Button("Use for pairing") { pairingAddress = service.endpoint }
                                    } else {
                                        Button(model.wirelessConnected(service) ? "Connected" : "Connect") { connectAddress = service.endpoint; model.connect(service.endpoint) }
                                            .disabled(model.wirelessConnected(service) || model.busy)
                                    }
                                }
                                if let failure = model.wirelessFailures[service.endpoint], !model.wirelessConnected(service) {
                                    Text(failure).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(.vertical, 12)
                            Divider()
                        }
                        instruction("Paired phones reconnect automatically. To pair a new phone, open “Pair device with pairing code” on the phone.")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pair device").font(.system(size: 13, weight: .semibold))
                        instruction("Select the pairing service above or enter its IP and port. Enter the six-digit code shown on your phone.")
                        labeledField("Pairing address", placeholder: "192.168.1.10:37000", text: $pairingAddress)
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Pairing code").font(.system(size: 12)).foregroundStyle(.secondary)
                                SecureField("Six-digit code", text: $code).accessibilityLabel("Pairing code")
                            }
                            Button("Pair") { model.connect(pairingAddress, pairCode: code); code = "" }
                                .disabled(model.busy || pairingAddress.isEmpty || code.count != 6)
                        }
                    }
                    Divider()
                    DisclosureGroup("Connect manually", isExpanded: $manualConnection) {
                        VStack(alignment: .leading, spacing: 12) {
                            instruction("Use the IP and port on the main Wireless debugging page. The connection port differs from the pairing port.")
                            HStack(alignment: .bottom, spacing: 12) {
                                labeledField("Connection address", placeholder: "192.168.1.10:39000", text: $connectAddress)
                                Button("Connect") { model.connect(connectAddress) }.disabled(model.busy || connectAddress.isEmpty)
                            }
                        }.padding(.top, 12)
                    }.font(.system(size: 13))
                    if model.busy { HStack { ProgressView().controlSize(.small); Text("Connecting…").font(.system(size: 12)) } }
                    if let error = model.error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    if !model.devices.isEmpty { instruction(model.status) }
                    DisclosureGroup("Connection activity") {
                        Text(String(model.logs.suffix(1800))).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }.font(.system(size: 13))
                }.padding(24)
            }
        }.textFieldStyle(.roundedBorder).frame(width: 600, height: 640).background(canvas).preferredColorScheme(.dark)
            .onAppear { model.startWirelessDiscovery() }
    }

    private func instruction(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }

    private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(placeholder, text: text).accessibilityLabel(title)
        }
    }
}
