import CoreAudio
import Foundation
import SwiftUI
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    // Audio state
    private(set) var outputs: [AudioOutput] = []
    private(set) var currentOutputID: AudioDeviceID = 0
    private(set) var volume: Float = 0
    private(set) var isMuted = false
    private(set) var isStreaming = false

    // Discovery + now playing
    private(set) var homePods: [HomePodDiscovery.Found] = []
    private(set) var nowPlaying: NowPlaying?
    /// Where Music is playing to; nil until Music integration is on and Music is running.
    private(set) var musicRoute: MusicRoute?

    // Climate: the mini's temperature and humidity. nil until a ClimateSource is connected.
    private(set) var climate: ClimateReading?
    var useFahrenheit: Bool {
        didSet { UserDefaults.standard.set(useFahrenheit, forKey: "useFahrenheit") }
    }
    /// Where the readings come from; see ClimateSource. Started once the Accessibility permission exists.
    var climateSource: ClimateSource? {
        didSet { climateSource?.start { [weak self] reading in self?.climate = reading } }
    }
    var climateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(climateEnabled, forKey: "climateEnabled")
            if climateEnabled { startClimateIfPossible() } else { climateSource = nil; climate = nil }
        }
    }
    private(set) var axTrusted = HomeAX.isTrusted

    // Sleep timer
    private(set) var sleepRemaining: Int?

    // Settings
    var volumeCap: Float {
        didSet { UserDefaults.standard.set(volumeCap, forKey: "volumeCap") }
    }

    /// Reading Music/Spotify triggers a one-time macOS Automation prompt, so it is opt-in.
    var showNowPlaying: Bool {
        didSet {
            UserDefaults.standard.set(showNowPlaying, forKey: "showNowPlaying")
            if showNowPlaying { readNowPlaying() } else { nowPlaying = nil }
        }
    }
    var popoverVisible = false

    private var mutedVolume: Float?
    private var lastVolumeSet = Date.distantPast
    private var trackMisses = 0
    private var routeMisses = 0
    private var previousOutputID: AudioDeviceID?
    private var sleepTask: Task<Void, Never>?
    private let discovery = HomePodDiscovery()
    private var timer: Timer?
    private var tick = 0

    init() {
        let stored = UserDefaults.standard.float(forKey: "volumeCap")
        volumeCap = stored == 0 ? 1 : stored
        showNowPlaying = UserDefaults.standard.bool(forKey: "showNowPlaying")
        useFahrenheit = UserDefaults.standard.bool(forKey: "useFahrenheit")
        climateEnabled = UserDefaults.standard.object(forKey: "climateEnabled") as? Bool ?? true
        // The pod render takes a moment; do it now rather than when the popover first opens.
        Task.detached(priority: .utility) { _ = PodRenderer.image }
        discovery.onChange = { [weak self] pods in self?.homePods = pods }
        discovery.start()
        refresh()
        startClimateIfPossible()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pulse() }
        }
    }

    // MARK: Derived

    var airPlayOutput: AudioOutput? { outputs.first(where: \.isAirPlay) }
    var currentOutput: AudioOutput? { outputs.first { $0.id == currentOutputID } }
    /// The whole Mac's sound is going to the HomePod.
    var systemConnected: Bool { currentOutput?.isAirPlay == true }
    /// Only Music is going to the HomePod (the one route an app can set up by itself).
    var musicOnHomePod: Bool { musicRoute.map { !$0.isComputer } ?? false }
    var isConnected: Bool { systemConnected || musicOnHomePod }
    /// The AirPlay output reports itself as just "AirPlay", so prefer the name Bonjour found.
    var homePodName: String { homePods.first?.name ?? airPlayOutput?.name ?? "HomePod mini" }
    var outputLabel: String {
        if systemConnected { return homePodName }
        if musicOnHomePod { return "Music → HomePod" }
        guard let current = currentOutput else { return "—" }
        return current.name.replacingOccurrences(of: " Speakers", with: "")
    }
    var isOnline: Bool { !homePods.isEmpty || airPlayOutput != nil }
    /// The colour the whole popover takes on, picked from the current track.
    var tint: Color { Theme.tint(for: nowPlaying.map { $0.title + $0.artist }) }
    var isPlaying: Bool { nowPlaying?.isPlaying ?? isStreaming }

    var statusText: String {
        if systemConnected { return "Connected · all Mac sound" }
        if musicOnHomePod { return "Connected · Music only" }
        return isOnline ? "Online · tap Use HomePod" : "Searching…"
    }

    // MARK: Refresh

    private static let trace = CommandLine.arguments.contains("--trace")

    private func pulse() {
        tick += 1
        // Nobody is watching the popover: the menu-bar number only needs a slow refresh.
        if !popoverVisible, !Self.trace, tick % 4 != 0 { return }
        refresh()
        if tick % 4 == 0, popoverVisible || Self.trace { readNowPlaying() }
        if Self.trace {
            NSLog("TRACE conn=\(isConnected) sys=\(systemConnected) music=\(musicRoute.map { "\($0.name)@\($0.volume)" } ?? "nil") np=\(nowPlaying?.title ?? "nil") playing=\(nowPlaying?.isPlaying ?? false) streaming=\(isStreaming) vol=\(volume) clim=\(climate.map { "\($0.temperatureC)C/\($0.humidity)%" } ?? "nil") tint=\(model_tintKey)")
        }
    }

    private var model_tintKey: String { nowPlaying.map { $0.title + $0.artist } ?? "-" }

    func refresh() {
        // Only publish what actually changed: every set of an observed property re-evaluates the UI.
        let newOutputs = CoreAudioKit.outputs()
        if newOutputs != outputs { outputs = newOutputs }
        let trusted = HomeAX.isTrusted
        if trusted != axTrusted { axTrusted = trusted; startClimateIfPossible() }
        let newDefault = CoreAudioKit.defaultOutput()
        if newDefault != currentOutputID { currentOutputID = newDefault }
        if let current = currentOutput, !current.isAirPlay { previousOutputID = current.id }

        // After the user sets the volume, the device takes a moment to report it, so ignore what it
        // says for a bit; otherwise the slider snaps back to the old value mid-drag.
        let userIsSetting = Date().timeIntervalSince(lastVolumeSet) < 1.5

        guard let current = currentOutput, current.isAirPlay else {
            if isStreaming { isStreaming = false }
            if let route = musicRoute, musicOnHomePod {
                if mutedVolume == nil, !userIsSetting, abs(volume - route.volume) > 0.002 { volume = route.volume }
                let muted = mutedVolume != nil
                if muted != isMuted { isMuted = muted }
            }
            return
        }
        if !userIsSetting, let v = CoreAudioKit.volume(of: current.id), abs(v - volume) > 0.002 { volume = v }
        let muted = CoreAudioKit.supportsMute(current.id) ? CoreAudioKit.isMuted(current.id) : mutedVolume != nil
        if muted != isMuted { isMuted = muted }
        let streaming = CoreAudioKit.isActive(current.id)
        if streaming != isStreaming { isStreaming = streaming }
    }

    private func readNowPlaying() {
        guard showNowPlaying, !CommandLine.arguments.contains("--demo") else { return }
        Task.detached(priority: .utility) {
            let track = NowPlayingReader.read()
            let route = MusicAirPlay.currentRoute()
            await MainActor.run {
                // A single failed script read must not blank the title and tint for a moment.
                if let track {
                    self.trackMisses = 0
                    if track != self.nowPlaying { self.nowPlaying = track }
                } else {
                    self.trackMisses += 1
                    if self.trackMisses >= 3, self.nowPlaying != nil { self.nowPlaying = nil }
                }
                if let route {
                    self.routeMisses = 0
                    if route != self.musicRoute { self.musicRoute = route }
                } else {
                    self.routeMisses += 1
                    if self.routeMisses >= 3, self.musicRoute != nil { self.musicRoute = nil }
                }
            }
        }
    }

    /// Dev aid for `--snapshot --demo`: fake a connected, playing HomePod so the layout can be previewed.
    func applyDemo() {
        musicRoute = MusicRoute(name: "Dr’s Homepod", volume: 0.62)
        nowPlaying = NowPlaying(app: "Music", title: "Ek Din Bik Jayega", artist: "Mukesh", isPlaying: true)
        volume = 0.62
        isStreaming = true
        climate = ClimateReading(temperatureC: 27.0, humidity: 46, date: Date())
    }

    // MARK: Actions

    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), volumeCap)
        lastVolumeSet = Date()
        if let current = currentOutput, current.isAirPlay {
            volume = clamped
            if mutedVolume != nil { mutedVolume = nil; CoreAudioKit.setMuted(false, of: current.id) }
            CoreAudioKit.setVolume(clamped, of: current.id)
        } else if musicOnHomePod, let route = musicRoute {
            volume = clamped
            mutedVolume = nil
            musicRoute = MusicRoute(name: route.name, volume: clamped)
            let percent = Int((clamped * 100).rounded())
            Task.detached(priority: .userInitiated) { MusicAirPlay.setVolume(percent) }
        }
    }

    func nudge(_ delta: Float) { setVolume(volume + delta) }

    func toggleMute() {
        if let current = currentOutput, current.isAirPlay, CoreAudioKit.supportsMute(current.id) {
            CoreAudioKit.setMuted(!isMuted, of: current.id)
            isMuted.toggle()
        } else if let restore = mutedVolume {
            // No real mute on this route: "mute" is volume 0, remembered so it can be restored.
            setVolume(restore)
            mutedVolume = nil
            isMuted = false
        } else if isConnected {
            let remembered = volume
            setVolume(0)
            mutedVolume = remembered
            isMuted = true
        }
    }

    /// Start using the HomePod. macOS only lets the user (not an app) choose the system output,
    /// so when it isn't already available that way, send Music to it.
    func connect() {
        if let pod = airPlayOutput {
            CoreAudioKit.setDefaultOutput(pod.id)
            refresh()
            return
        }
        showNowPlaying = true
        let name = homePodName
        Task.detached(priority: .userInitiated) {
            let route = MusicAirPlay.route(toDeviceNamed: name)
            await MainActor.run { if let route { self.musicRoute = route; self.refresh() } }
        }
    }

    /// Power: stop using the HomePod (back to this Mac's speakers), or start.
    func togglePower() {
        if systemConnected {
            useOutput(outputs.first { $0.id == previousOutputID } ?? outputs.first { !$0.isAirPlay })
        } else if musicOnHomePod {
            togglePowerMusicOnly()
        } else {
            connect()
        }
    }

    func togglePowerMusicOnly() {
        guard musicOnHomePod else { return }
        musicRoute = MusicRoute(name: "Computer", volume: 1)
        Task.detached(priority: .userInitiated) { MusicAirPlay.routeToComputer() }
    }

    func useOutput(_ output: AudioOutput?) {
        guard let output else { return }
        CoreAudioKit.setDefaultOutput(output.id)
        refresh()
    }

    func play(_ key: MediaKey) { key.press() }

    // MARK: Sleep timer

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        let total = minutes * 60
        let fadeSeconds = 20
        sleepRemaining = total
        sleepTask = Task { [weak self] in
            var startVolume: Float?
            for remaining in stride(from: total, through: 0, by: -1) {
                guard let self, !Task.isCancelled else { return }
                self.sleepRemaining = remaining
                if remaining <= fadeSeconds, self.isConnected {
                    if startVolume == nil { startVolume = self.volume }
                    let base = startVolume ?? self.volume
                    self.setVolume(base * Float(remaining) / Float(fadeSeconds))
                }
                if remaining == 0 { break }
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            MediaKey.playPause.press()
            try? await Task.sleep(for: .seconds(1))
            if let startVolume { self.setVolume(startVolume) }
            self.sleepRemaining = nil
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepRemaining = nil
    }

    // MARK: Climate via the Home app

    var climateHint: String {
        if !climateEnabled { return "Off" }
        if !axTrusted { return "Needs access" }
        return "Reading…"
    }

    private func startClimateIfPossible() {
        guard climateEnabled, axTrusted, climateSource == nil, !CommandLine.arguments.contains("--demo") else { return }
        climateSource = HomeClimateSource()
    }

    /// Asks for the Accessibility permission the reader needs. Only the user can grant it.
    func connectClimate() {
        if !HomeAX.isTrusted { HomeAX.promptForTrust() }
    }

    func refreshClimateNow() { (climateSource as? HomeClimateSource)?.refresh() }

    // MARK: Login item

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login failed: \(error.localizedDescription)")
        }
    }
}
