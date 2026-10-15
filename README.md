# Hum

A menu-bar app for a HomePod. Dark popover, big volume readout, slider, mute, transport,
sleep timer and a volume limit, styled after the "AC status bar" reference.

## Run

```bash
./build.sh run     # dev build: builds build/Hum.app as "Hum Dev", signs it, launches it
```

Click the HomePod icon in the menu bar. First launch asks for Local Network (to find the
HomePod) and, when Music/Spotify is running, Automation (to show and control the track).

The dev build is `com.hitesh.Hum.dev`, separate from the release's `com.hitesh.Hum`. macOS ties each
permission to the app's signature, so the two can't share one: with a single bundle ID, running either copy
would turn the other's Accessibility grant stale (still "on" in System Settings, but not counted).

## Release (for other people)

```bash
./package.sh       # universal build, Developer ID signed, notarized: build/Hum-<version>.dmg
```

Needs a **Developer ID Application** certificate in the keychain and notarytool credentials saved once:
`xcrun notarytool store-credentials hum-notary --apple-id <apple id> --team-id <team id>`.
Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Info.plist` for each release.

What people are asked for, and when:

| Permission | When | Without it |
|------------|------|------------|
| Local Network | first launch | the HomePod is never found |
| Automation (Music, Spotify) | turning on "Show now playing", or pressing play when no other route works | no track shown; controls fall back to media keys |
| Accessibility | clicking "Needs access" in the climate strip, the menu, or pressing play when nothing else can | no temperature / humidity; media keys (for apps other than Music and Spotify) do nothing |

## How it works

| Piece | Mechanism |
|-------|-----------|
| Connect | System AirPlay button (`AVRoutePickerView`) — the only public way to route Mac audio to a HomePod |
| Volume / mute | CoreAudio virtual main volume on the AirPlay output device |
| Power | Switches the default output between the HomePod and the previous device |
| Play / pause / next | AppleScript to Music / Spotify when the track is theirs; otherwise media keys (F7-F9), which need Accessibility. Without Accessibility, whichever of Music / Spotify has a track, then a prompt for the permission |
| Now playing | AppleScript to Music / Spotify, only when already running |
| Online status | Bonjour browse for `_airplay._tcp` with model `AudioAccessory*` |
| Sleep timer | 20 s fade-out, then pause, then volume restored |

Controls apply to the Mac's AirPlay output, so they only affect audio sent from this Mac.

`Hum --snapshot out.png` renders the popover to a PNG (the AirPlay button shows as a
placeholder there).

## Temperature and humidity

The mini's sensors show beside the pod: an arc gauge for temperature and a droplet that fills for humidity.

Source: the Home app, read through the Accessibility API (`HomeClimateSource.swift`). Apple gives a Mac app
no public way to read the HomePod's sensor (HomeKit needs a paid developer account), so the app reads the
numbers the Home app shows. It needs the **Accessibility** permission (System Settings > Privacy & Security).

- Humidity only appears on the Home app's Climate page, and that window must be visible to navigate there.
  So on first run the app briefly shows Home, opens Climate, and hides it again. From then on it reads the
  page every 30 s while Home stays hidden (the hidden page keeps updating).
- Home is left on the Climate page. If you open it you will land there; press Back.
- Home averages every temperature and humidity sensor in the home. With one HomePod mini, that is its sensor.
- Reads English labels ("Temperature, 28.5°", "Humidity, 62%"); a macOS update or another language may break it.
- Menu (slider icon): turn it on/off, "Refresh temperature & humidity" to re-open the Climate page.

`Hum --dump-home-ax out.txt` writes everything the Home app exposes (for fixing the reader).
`Hum --snapshot out.png --demo` previews with sample numbers (27.0 degrees, 46%).
