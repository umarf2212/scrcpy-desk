import Foundation

struct Device: Identifiable, Equatable {
    let id: String
    let state: String
    let name: String
    var ready: Bool { state == "device" }
    var wireless: Bool { id.contains(":") || id.contains("._tcp") }
    static func parse(_ text: String) -> [Device] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard fields.count >= 2, ["device", "unauthorized", "offline", "recovery", "sideload", "no"].contains(fields[1]) else { return nil }
            let model = fields.first(where: { $0.hasPrefix("model:") }).map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") }
            return Device(id: fields[0], state: fields[1], name: model ?? fields[0])
        }
    }
}

enum InputError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

// Tokenization only: never invoke a shell or evaluate substitutions.
func splitArguments(_ text: String) throws -> [String] {
    var result: [String] = [], current = "", quote: Character?, escaped = false, started = false
    for c in text {
        if escaped { current.append(c); escaped = false; started = true; continue }
        if c == "\\" && quote != "'" { escaped = true; started = true; continue }
        if let q = quote {
            if c == q { quote = nil } else { current.append(c) }
            continue
        }
        if c == "\"" || c == "'" { quote = c; started = true }
        else if c.isWhitespace {
            if started { result.append(current); current = ""; started = false }
        } else { current.append(c); started = true }
    }
    guard quote == nil, !escaped else { throw InputError.invalid("Close the quote or complete the escape in additional arguments.") }
    if started { result.append(current) }
    return result
}
func shellQuote(_ text: String) -> String {
    let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:=@+-")
    return !text.isEmpty && text.unicodeScalars.allSatisfy(safe.contains) ? text : "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

struct Options: Codable, Equatable {
    var size = "1920", fps = "60", bitrate = "8", codec = "h264"
    var audio = true, audioSource = "output", audioCodec = "opus"
    var control = true, clipboard = true, keyboard = "sdk", mouse = "sdk"
    var screenOff = false, awake = false, touches = false
    var onTop = false, fullscreen = false, borderless = false
    var orientation = "0", title = "", crop = "", extra = ""
    var recording = false, recordPath = ""
    mutating func preset(_ name: String) {
        switch name {
        case "Responsive": size = "1280"; fps = "60"; bitrate = "4"; codec = "h264"
        case "Crisp": size = "0"; fps = "60"; bitrate = "16"; codec = "h265"
        default: size = "1920"; fps = "60"; bitrate = "8"; codec = "h264"
        }
    }
    var presetName: String {
        if size == "1280" && fps == "60" && bitrate == "4" && codec == "h264" { return "Responsive" }
        if size == "1920" && fps == "60" && bitrate == "8" && codec == "h264" { return "Balanced" }
        if size == "0" && fps == "60" && bitrate == "16" && codec == "h265" { return "Crisp" }
        return "Custom"
    }
    func arguments(serial: String) throws -> [String] {
        guard let rate = Double(bitrate), rate.isFinite, rate > 0, rate <= 1000 else { throw InputError.invalid("Video bitrate must be between 0 and 1000 Mbps.") }
        var args = ["--serial=\(serial)", "--max-size=\(size)", "--max-fps=\(fps)", "--video-bit-rate=\(Int(rate * 1_000_000))", "--video-codec=\(codec)"]
        if audio { args += ["--audio-source=\(audioSource)", "--audio-codec=\(audioCodec)"] } else { args.append("--no-audio") }
        if control {
            args += ["--keyboard=\(keyboard)", "--mouse=\(mouse)"]
            if screenOff { args.append("--turn-screen-off") }
            if awake { args.append("--stay-awake") }
            if touches { args.append("--show-touches") }
        } else { args.append("--no-control") }
        if !clipboard { args.append("--no-clipboard-autosync") }
        if onTop { args.append("--always-on-top") }
        if fullscreen { args.append("--fullscreen") }
        if borderless { args.append("--window-borderless") }
        if orientation != "0" { args.append("--capture-orientation=\(orientation)") }
        if !title.isEmpty { args.append("--window-title=\(title)") }
        if !crop.isEmpty {
            let parts = crop.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
            guard parts.count == 4, parts[0] > 0, parts[1] > 0, parts[2] >= 0, parts[3] >= 0 else { throw InputError.invalid("Crop must be width:height:x:y, for example 1080:1920:0:0.") }
            args.append("--crop=\(crop)")
        }
        if recording {
            guard !recordPath.isEmpty, ["mp4", "mkv"].contains(URL(fileURLWithPath: recordPath).pathExtension.lowercased()) else { throw InputError.invalid("Choose an MP4 or MKV recording file.") }
            args.append("--record=\(recordPath)")
        }
        args += try splitArguments(extra)
        return args
    }
}

func validateEndpoint(_ input: String) throws -> String {
    let endpoint = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !endpoint.isEmpty, !endpoint.hasPrefix("-"), !endpoint.contains(where: { $0.isWhitespace }),
          let colon = endpoint.lastIndex(of: ":"), colon != endpoint.startIndex,
          let port = Int(endpoint[endpoint.index(after: colon)...]), (1...65535).contains(port) else {
        throw InputError.invalid("Enter the IP address and port shown on your phone, for example 192.168.1.20:37123.")
    }
    return endpoint
}
