import SwiftUI

struct PopoverView: View {
    let model: AppModel
    var previewAppeared = false

    private var percent: Int { Int((model.volume * 100).rounded()) }

    @State private var appeared = false
    private var shown: Bool { appeared || previewAppeared }

    private var glowStrength: Double {
        guard model.isConnected else { return 0.15 }
        return model.isPlaying ? 0.65 + 0.5 * Double(model.volume) : 0.3
    }

    /// Where the pod sits in the main area (its centre), and how big it is.
    private let podScale: CGFloat = 1.65
    private let podCenter = CGPoint(x: 212, y: 126)

    var body: some View {
        VStack(spacing: 0) {
            header.appear(shown, 0)
            main.padding(.top, 10).appear(shown, 1)
            ClimateStrip(reading: model.climate, emptyCaption: model.climateHint, fahrenheit: model.useFahrenheit) {
                withAnimation(.smooth(duration: 0.4)) { model.useFahrenheit.toggle() }
            }
            .padding(.top, 12)
            .appear(shown, 2)
            dock.padding(.top, 14).appear(shown, 3)
            footer.padding(.top, 12).appear(shown, 4)
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
        .frame(width: 380)
        .background(AuroraBackground(tint: model.tint, strength: glowStrength))
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.isConnected)
        .preferredColorScheme(.dark)
        .onAppear {
            model.refresh()
            model.popoverVisible = true
            // Hide instantly (no animation) so there is no flash of the finished layout, then animate in.
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) { appeared = false }
            DispatchQueue.main.async { appeared = true }
        }
        .onDisappear {
            model.popoverVisible = false
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) { appeared = false }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "homepodmini.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
            Text(model.homePodName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            statusChip
            Spacer()
            RoundIconButton(
                systemName: "power",
                size: 34,
                tint: model.isConnected ? model.tint : .white.opacity(0.55)
            ) { model.togglePower() }
            .help(model.isConnected ? "Send sound back to this Mac" : "Use HomePod")
            .disabled(!model.isConnected && !model.isOnline)
        }
        .frame(height: 36)
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isConnected ? Theme.live : (model.isOnline ? Theme.accent : Theme.tertiary))
                .frame(width: 6, height: 6)
                .shadow(color: model.isConnected ? Theme.live : .clear, radius: 4)
            Text(model.isConnected ? "Connected" : (model.isOnline ? "Online" : "Searching…"))
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Theme.cardStroke))
        .animation(.smooth(duration: 0.4), value: model.isConnected)
    }

    // MARK: Main stage

    private var main: some View {
        ZStack(alignment: .topLeading) {
            HomePodArt(
                scale: podScale,
                isPlaying: model.isConnected && model.isPlaying,
                isMuted: model.isMuted,
                tint: model.tint,
                level: model.volume
            )
            .opacity(model.isConnected ? 1 : 0.4)
            .position(podCenter)

            if !model.isConnected {
                connectPill
                    .position(podCenter)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
            }

            textColumn
            volumeColumn
        }
        .frame(width: 344, height: 262)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOW PLAYING")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Theme.secondary)

            Group {
                TrackTitle(title: model.nowPlaying?.title ?? "Nothing playing", tint: model.tint)
                    .padding(.top, 8)
                Text(model.nowPlaying.map { ($0.artist.isEmpty ? "" : $0.artist + " · ") + $0.app } ?? "Music or Spotify")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .padding(.top, 9)
            }
            .id(model.nowPlaying?.title ?? "")
            .transition(.asymmetric(
                insertion: .offset(y: 10).combined(with: .opacity),
                removal: .offset(y: -10).combined(with: .opacity)
            ))

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                RoundIconButton(systemName: "backward.fill", size: 36) { model.play(.previous) }
                RoundIconButton(systemName: model.isPlaying ? "pause.fill" : "play.fill", size: 46, filledGlow: model.tint) {
                    model.play(.playPause)
                }
                RoundIconButton(systemName: "forward.fill", size: 36) { model.play(.next) }
            }

            // The room the mute pill used to take, so the transport row stays where it was.
            Color.clear.frame(height: 38)
        }
        .frame(width: 196, height: 262, alignment: .topLeading)
        .animation(.smooth(duration: 0.4), value: model.nowPlaying?.title)
    }

    private var volumeColumn: some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(model.isConnected ? "\(percent)" : "–")
                    .font(.system(size: 21, weight: .regular))
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
            }
            .foregroundStyle(model.isConnected ? .white : Theme.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            VerticalVolumeSlider(value: model.volume, cap: model.volumeCap, tint: model.tint) { model.setVolume($0) }
                .frame(width: 36, height: 176)
                .disabled(!model.isConnected)
                .opacity(model.isConnected ? 1 : 0.35)

            RoundIconButton(
                systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                size: 34,
                tint: model.isMuted ? model.tint : .white.opacity(0.75)
            ) { model.toggleMute() }
            .help(model.isMuted ? "Unmute" : "Mute")
            .disabled(!model.isConnected)
            .opacity(model.isConnected ? 1 : 0.5)
        }
        .frame(width: 44)
        .frame(width: 344, height: 262, alignment: .topTrailing)
        .animation(.smooth(duration: 0.4), value: model.isConnected)
    }

    // MARK: Connect

    private var connectPill: some View {
        Button { model.connect() } label: {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
                Text("Use HomePod")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.black.opacity(0.7)))
            .overlay(Capsule().strokeBorder(Theme.cardStroke))
        }
        .buttonStyle(PressableStyle())
        .disabled(!model.isOnline)
    }

    // MARK: Dock

    private var dock: some View {
        HStack(spacing: 6) {
            Menu {
                Button(model.musicOnHomePod ? "✓ Music on HomePod" : "Play Music on HomePod") { model.connect() }
                    .disabled(!model.isOnline)
                Button("Music on this Mac") { model.togglePowerMusicOnly() }
                Divider()
                Section("Mac sound output") {
                    ForEach(model.outputs) { output in
                        Button((output.id == model.currentOutputID ? "✓ " : "") + (output.isAirPlay ? model.homePodName : output.name)) {
                            model.useOutput(output)
                        }
                    }
                }
                Divider()
                Button("Sound settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
            } label: {
                DockItem(title: "Output", value: model.outputLabel) {
                    dockGlyph("airplayaudio", color: model.isConnected ? Theme.live : .white.opacity(0.82))
                }
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)

            Menu {
                Button("Off") { model.cancelSleepTimer() }
                Divider()
                Button("15 minutes") { model.startSleepTimer(minutes: 15) }
                Button("30 minutes") { model.startSleepTimer(minutes: 30) }
                Button("1 hour") { model.startSleepTimer(minutes: 60) }
            } label: {
                DockItem(title: "Sleep", value: sleepText) { dockGlyph(model.sleepRemaining == nil ? "moon" : "moon.fill") }
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)

            Menu {
                ForEach([100, 80, 60, 40], id: \.self) { pct in
                    Button(pct == 100 ? "No limit" : "\(pct)%") { model.volumeCap = Float(pct) / 100 }
                }
            } label: {
                DockItem(title: "Limit", value: model.volumeCap >= 1 ? "None" : "\(Int(model.volumeCap * 100))%") {
                    dockGlyph("speaker.wave.2")
                }
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain)

            DockItem(title: "Source", value: model.nowPlaying?.app ?? "—") { dockGlyph("music.note") }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
    }

    private var sleepText: String {
        guard let s = model.sleepRemaining else { return "Off" }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isConnected ? Theme.live : (model.isOnline ? Theme.accent : Theme.tertiary))
                .frame(width: 6, height: 6)
                .animation(.smooth(duration: 0.4), value: model.isConnected)
            Text(model.statusText)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
            Spacer()
            Menu {
                Button(model.launchesAtLogin ? "✓ Launch at login" : "Launch at login") {
                    model.setLaunchAtLogin(!model.launchesAtLogin)
                }
                Button(model.climateEnabled ? "✓ Temperature & humidity (Home app)" : "Temperature & humidity (Home app)") {
                    model.climateEnabled.toggle()
                }
                if model.climateEnabled {
                    if model.axTrusted {
                        Button("Refresh temperature & humidity") { model.refreshClimateNow() }
                    } else {
                        Button("Grant Accessibility access…") { model.connectClimate() }
                    }
                }
                Button(model.useFahrenheit ? "✓ Temperature in °F" : "Temperature in °F") {
                    model.useFahrenheit.toggle()
                }
                Button(model.showNowPlaying ? "✓ Show now playing (Music, Spotify)" : "Show now playing (Music, Spotify)") {
                    model.showNowPlaying.toggle()
                }
                Divider()
                Button("Quit Hum") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(PressableStyle(scale: 0.95))
        }
    }
}
