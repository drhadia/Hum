import AppKit
import SwiftUI

/// The app icon, drawn at 1024 x 1024 with the standard macOS margin around the rounded tile.
struct AppIconArt: View {
    private let tile: CGFloat = 824

    var body: some View {
        ZStack {
            tileView
                .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
        }
        .frame(width: 1024, height: 1024)
    }

    private var tileView: some View {
        RoundedRectangle(cornerRadius: 186, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.13, green: 0.08, blue: 0.50), location: 0),
                        .init(color: Color(red: 0.47, green: 0.16, blue: 0.82), location: 0.38),
                        .init(color: Color(red: 0.96, green: 0.25, blue: 0.52), location: 0.72),
                        .init(color: Color(red: 1.00, green: 0.62, blue: 0.24), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: tile, height: tile)
            .overlay(colourPools)
            .overlay(rings)
            .overlay(pod)
            .overlay(
                // soft inner rim, so the tile reads as a lit glass edge
                RoundedRectangle(cornerRadius: 186, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
            )
    }

    private func pool(_ color: Color, _ opacity: Double, _ radius: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: x, y: y)
    }

    private var colourPools: some View {
        ZStack {
            pool(Color(red: 0.10, green: 0.85, blue: 0.95), 0.75, 330, x: -250, y: 260)
            pool(Color(red: 1.0, green: 0.35, blue: 0.75), 0.60, 280, x: 250, y: -250)
            pool(.white, 0.22, 300, x: 0, y: -60)
        }
        .frame(width: tile, height: tile)
        .clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous))
    }

    private var rings: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let grow = CGFloat(i) * 118
                Circle()
                    .stroke(Color.white.opacity(0.42 - 0.09 * Double(i)), lineWidth: 7 - CGFloat(i))
                    .frame(width: 470 + grow, height: 470 + grow)
            }
        }
        .offset(y: 23)
        .frame(width: tile, height: tile)
        .clipShape(RoundedRectangle(cornerRadius: 186, style: .continuous))
    }

    private var pod: some View {
        ZStack {
            // coloured light spilling out of the lit top
            pool(Color(red: 1, green: 0.2, blue: 0.6), 0.85, 150, x: -90, y: -175)
            pool(Color(red: 0.1, green: 0.9, blue: 1), 0.85, 150, x: 90, y: -175)
            pool(Color(red: 0.6, green: 0.3, blue: 1), 0.8, 130, x: 0, y: -200)
            HomePodMiniBody(scale: 4.6, tint: .pink, glow: 1, pulse: 0.8, angle: 30, rainbow: true)
        }
        .offset(y: 28)
    }
}

enum IconWriter {
    /// Dev aid: `Hum --icon <dir>` writes AppIcon.iconset PNGs into <dir>.
    @MainActor
    static func write(to dir: String) {
        let renderer = ImageRenderer(content: AppIconArt())
        renderer.scale = 1
        guard let master = renderer.cgImage else { NSLog("icon render failed"); return }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(name: String, px: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, px) in sizes {
            guard let ctx = CGContext(
                data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            ctx.interpolationQuality = .high
            ctx.draw(master, in: CGRect(x: 0, y: 0, width: px, height: px))
            guard let img = ctx.makeImage() else { continue }
            let rep = NSBitmapImageRep(cgImage: img)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }
}
