import Foundation
@main struct CoreTests {
    static func main() throws {
        var checks = 0
        func check(_ ok: @autoclosure () -> Bool, _ message: String) { precondition(ok(), message); checks += 1 }
        let parsed = Device.parse("List of devices attached\nABC device product:test model:Pixel_9 device:test\nDEF unauthorized usb:1\n192.168.1.2:4567 offline\n* daemon started successfully *\n")
        check(parsed.count == 3, "parse devices")
        check(parsed[0].name == "Pixel 9" && parsed[0].ready, "model and ready")
        check(!parsed[1].ready && parsed[2].wireless, "authorization and transport")
        let quoted = try splitArguments("--window-title='My phone' --crop=10:20:0:0 --foo=\"a b\" empty '' literal\\ value")
        check(quoted == ["--window-title=My phone", "--crop=10:20:0:0", "--foo=a b", "empty", "", "literal value"], "quoted arguments")
        let injection = try splitArguments("--window-title='$(touch /tmp/never)' ';' '`whoami`'")
        check(injection == ["--window-title=$(touch /tmp/never)", ";", "`whoami`"], "shell syntax stays literal")
        do { _ = try splitArguments("'open"); preconditionFailure("unterminated quote accepted") } catch { checks += 1 }
        let services = WirelessService.parse("List of discovered mdns services\nadb-SERIAL-random _adb-tls-connect._tcp 192.168.1.4:43787\nadb-SERIAL-other _adb-tls-pairing._tcp. [fe80::1%en0]:37123\nbad _http._tcp 192.168.1.4:80\nbad _adb-tls-connect._tcp host:70000\n")
        check(services.count == 2, "parse only valid Android services")
        check(services[0].kind == .connection && services[0].endpoint == "192.168.1.4:43787", "connection endpoint")
        check(services[1].kind == .pairing && services[1].endpoint == "[fe80::1%en0]:37123", "pairing IPv6 endpoint")
        check(services[0].deviceKey == services[1].deviceKey, "associate pairing with connection despite random suffix")
        check(services[0].id != services[1].id, "keep pairing and connection distinct")
        check(wirelessFailureMessage("failed to connect: No route to host").contains("Local Network"), "actionable local-network recovery")
        check(wirelessFailureMessage("failed to authenticate").contains("Local Network") == false, "authentication is not a routing failure")
        var displayOptions = Options()
        displayOptions.codec = "h265"; displayOptions.bitrate = "30"
        let oldSettings = try JSONEncoder().encode(displayOptions)
        let migrated = try JSONDecoder().decode(Options.self, from: oldSettings)
        check(!migrated.desktopSettings.enabled && migrated.codec == "h265" && migrated.bitrate == "30", "legacy settings preserved")
        displayOptions.extra = "--new-display=1920x1080/160 --print-fps --window-title='A desktop with spaces'"
        displayOptions.setDesktopEnabled(true)
        let desktopArgs = try displayOptions.arguments(serial: "x")
        check(desktopArgs.filter { $0.hasPrefix("--new-display") } == ["--new-display=1920x1080/160"], "single desktop argument after migration")
        check(desktopArgs.contains("--print-fps") && desktopArgs.contains("--window-title=A desktop with spaces"), "preserve unrelated advanced options")
        displayOptions.desktopSettings.resolution = "2560x1440"; displayOptions.desktopSettings.dpi = "240"
        let savedDesktop = try JSONDecoder().decode(Options.self, from: JSONEncoder().encode(displayOptions))
        check(tryOptions(savedDesktop).contains("--new-display=2560x1440/240"), "desktop configuration persists")
        displayOptions.setDesktopEnabled(false)
        check(!tryOptions(displayOptions).contains(where: { $0.hasPrefix("--new-display") }), "toggle off returns to phone display")
        check(displayOptions.desktopSettings.resolution == "2560x1440", "remember desktop settings while off")
        displayOptions.setDesktopEnabled(true); displayOptions.extra = "--display-id=2"
        do { _ = try displayOptions.arguments(serial: "x"); preconditionFailure("conflicting display accepted") } catch { checks += 1 }
        displayOptions.extra = ""; displayOptions.desktopSettings.dpi = "0"
        do { _ = try displayOptions.arguments(serial: "x"); preconditionFailure("invalid desktop density accepted") } catch { checks += 1 }
        var options = Options()
        var args = try options.arguments(serial: "test phone")
        check(args.contains("--serial=test phone"), "serial stays one argument")
        check(args.contains("--video-bit-rate=8000000"), "bitrate conversion")
        options.control = false; options.screenOff = true; options.awake = true; options.touches = true; options.audio = false
        args = try options.arguments(serial: "abc")
        check(args.contains("--no-control") && args.contains("--no-audio"), "disable streams/control")
        check(!args.contains("--turn-screen-off") && !args.contains("--stay-awake") && !args.contains("--show-touches"), "control-only options suppressed")
        options.recording = true; options.recordPath = "/tmp/a movie.mkv"
        check(tryOptions(options).contains("--record=/tmp/a movie.mkv"), "recording path")
        options.recordPath = ""
        do { _ = try options.arguments(serial: "x"); preconditionFailure("missing recording path accepted") } catch { checks += 1 }
        options.recording = false; options.crop = "10:20:0:0"
        check(tryOptions(options).contains("--crop=10:20:0:0"), "valid crop")
        options.crop = "10:20:-1:0"
        do { _ = try options.arguments(serial: "x"); preconditionFailure("negative crop accepted") } catch { checks += 1 }
        options.crop = ""; options.bitrate = "nan"
        do { _ = try options.arguments(serial: "x"); preconditionFailure("nan accepted") } catch { checks += 1 }
        options.preset("Crisp"); check(options.presetName == "Crisp", "preset")
        let endpoint = try validateEndpoint("192.168.1.2:5555")
        check(endpoint == "192.168.1.2:5555", "endpoint")
        for invalid in ["", "-host:55", "foo", "host:70000", "host:0", "host:5 5"] {
            do { _ = try validateEndpoint(invalid); preconditionFailure("invalid endpoint accepted") } catch { checks += 1 }
        }
        let roundTrip = try JSONDecoder().decode(Options.self, from: JSONEncoder().encode(options))
        check(roundTrip == options, "settings persistence")
        print("Passed \(checks) core checks.")
    }
    static func tryOptions(_ o: Options) -> [String] { try! o.arguments(serial: "x") }
}
