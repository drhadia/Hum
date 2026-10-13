import SwiftUI

@main
struct HumApp: App {
    @State private var model = AppModel()

    init() {
        // Dev aid: `Hum --snapshot out.png` renders the popover to a PNG and exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--dump-home-ax"), i + 1 < args.count {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !HomeAX.isTrusted { HomeAX.promptForTrust() }
                try? HomeAX.dump().write(toFile: path, atomically: true, encoding: .utf8)
                exit(0)
            }
        }
        if args.contains("--window") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { SnapshotRenderer.showWindow() }
        }
        if args.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { SnapshotRenderer.openPopover() }
        }
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
            let dir = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                IconWriter.write(to: dir)
                exit(0)
            }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                SnapshotRenderer.write(to: path)
                exit(0)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.isConnected ? "homepodmini.fill" : "homepodmini")
                if model.isConnected {
                    Text(model.isMuted ? "Muted" : "\(Int((model.volume * 100).rounded()))%")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
