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
