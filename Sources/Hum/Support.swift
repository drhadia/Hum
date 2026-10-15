import AppKit
import Foundation
import Network

// MARK: - HomePod discovery

/// Watches Bonjour for AirPlay receivers and keeps the HomePods.
final class HomePodDiscovery {
    struct Found: Equatable {
        let name: String
        let model: String
    }

    var onChange: (([Found]) -> Void)?
    private var browser: NWBrowser?

    func start() {
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_airplay._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let pods: [Found] = results.compactMap { result in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                var model = ""
                if case let .bonjour(txt) = result.metadata { model = txt["model"] ?? "" }
                return model.hasPrefix("AudioAccessory") ? Found(name: name, model: model) : nil
            }
            DispatchQueue.main.async { self?.onChange?(pods.sorted { $0.name < $1.name }) }
        }
        b.start(queue: .global(qos: .utility))
        browser = b
    }
}

// MARK: - Media keys

/// Sends the same keys as the F7 / F8 / F9 row, so they reach whatever app owns Now Playing.
enum MediaKey: Int32 {
    case playPause = 16
    case next = 17
    case previous = 18

    func press() {
        for down in [true, false] {
            let state: Int32 = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((rawValue << 16) | (state << 8)),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Now Playing (Music / Spotify)

struct NowPlaying: Equatable {
    let app: String
    let title: String
    let artist: String
    let isPlaying: Bool
}

enum NowPlayingReader {
    static let sources: [(app: String, bundle: String)] = [
        ("Music", "com.apple.Music"),
        ("Spotify", "com.spotify.client"),
    ]

    /// Asks only apps that are already running, so polling never launches anything.
    static func read() -> NowPlaying? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var paused: NowPlaying?
        for source in sources where running.contains(source.bundle) {
            let script = """
            tell application "\(source.app)"
                if player state is stopped then return "stopped||"
                return (player state as string) & "|" & (name of current track) & "|" & (artist of current track)
            end tell
            """
            guard let out = ScriptRunner.run(script) else { continue }
            let parts = out.components(separatedBy: "|")
            guard parts.count >= 3, parts[0] != "stopped" else { continue }
            let track = NowPlaying(app: source.app, title: parts[1], artist: parts[2], isPlaying: parts[0] == "playing")
            if track.isPlaying { return track }
            paused = paused ?? track
        }
        return paused
    }
}

// MARK: - Transport (Music / Spotify)

/// Play / pause / skip through the player's own AppleScript. Media keys only work with the Accessibility
/// permission (macOS silently drops posted keys without it); this needs just the Automation permission
/// that reading the track already asked for.
enum PlayerControl {
    /// false when the app isn't running or the script failed, so the caller can fall back to media keys.
    static func send(_ command: String, to app: String) -> Bool {
        guard let source = NowPlayingReader.sources.first(where: { $0.app == app }),
              ScriptRunner.isRunning(source.bundle) else { return false }
        return ScriptRunner.run("""
        tell application "\(source.app)" to \(command)
        return "ok"
        """) == "ok"
    }

    static func command(for key: MediaKey, app: String) -> String {
        switch key {
        case .playPause: "playpause"
        case .next: "next track"
        // Music's "back track" restarts the song first, like its button and the F7 key.
        case .previous: app == "Music" ? "back track" : "previous track"
        }
    }
}

// MARK: - AppleScript runner

/// NSAppleScript is not thread-safe and blocks on the macOS Automation prompt, so every script
/// runs on one background queue. Never call these from the main thread.
enum ScriptRunner {
    private static let queue = DispatchQueue(label: "Hum.applescript", qos: .utility)

    // Compiling is the expensive part of an AppleScript call, and the same few scripts run every 2 s.
    private static var compiled: [String: NSAppleScript] = [:]

    static func run(_ source: String) -> String? {
        queue.sync {
            var error: NSDictionary?
            let script: NSAppleScript?
            if let cached = compiled[source] {
                script = cached
            } else {
                script = NSAppleScript(source: source)
                if compiled.count > 32 { compiled.removeAll() }
                if let script { compiled[source] = script }
            }
            let result = script?.executeAndReturnError(&error)
            if let error { NSLog("AppleScript error: \(error)") }
            return result?.stringValue
        }
    }

    static func isRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }
}

// MARK: - Music → HomePod

/// Where Music is currently playing to, and how loud that device is.
struct MusicRoute: Equatable {
    let name: String
    let volume: Float  // 0...1

    var isComputer: Bool { name == "Computer" }
}

/// Music's own AppleScript AirPlay support. Unlike the system output, an app can switch this,
/// and the device volume it sets is the HomePod's own.
enum MusicAirPlay {
    static let bundleID = "com.apple.Music"

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// nil when Music isn't running (so polling never launches it) or isn't scriptable yet.
    static func currentRoute() -> MusicRoute? {
        guard ScriptRunner.isRunning(bundleID) else { return nil }
        let script = """
        tell application "Music"
            set ds to current AirPlay devices
            if ds is {} then return ""
            set d to item 1 of ds
            return (name of d) & "~" & (sound volume of d)
        end tell
        """
        guard let out = ScriptRunner.run(script) else { return nil }
        let parts = out.components(separatedBy: "~")
        guard parts.count == 2, let v = Float(parts[1]) else { return nil }
        return MusicRoute(name: parts[0], volume: v / 100)
    }

    /// Sends Music to the named device. The Bonjour name uses a different apostrophe than Music's,
    /// so fall back to any device whose name contains "homepod".
    static func route(toDeviceNamed name: String) -> MusicRoute? {
        let script = """
        tell application "Music"
            set target to missing value
            repeat with d in (every AirPlay device)
                if (name of d) is \(quoted(name)) then set target to d
            end repeat
            if target is missing value then
                repeat with d in (every AirPlay device)
                    if (name of d) contains "homepod" then set target to d
                end repeat
            end if
            if target is missing value then return "notfound"
            set current AirPlay devices to {target}
            return "ok"
        end tell
        """
        guard ScriptRunner.run(script) == "ok" else { return nil }
        return currentRoute()
    }

    static func routeToComputer() {
        _ = ScriptRunner.run("""
        tell application "Music"
            set current AirPlay devices to {AirPlay device "Computer"}
        end tell
        """)
    }

    static func setVolume(_ percent: Int) {
        guard ScriptRunner.isRunning(bundleID) else { return }
        _ = ScriptRunner.run("""
        tell application "Music"
            repeat with d in (current AirPlay devices)
                set sound volume of d to \(min(max(percent, 0), 100))
            end repeat
        end tell
        """)
    }
}
