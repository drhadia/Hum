import SwiftUI

/// The popover's atmosphere: a glow from the top in the track's colour, and two soft blobs in
/// neighbouring hues that drift slowly. Built from gradients (no blur filters) so it stays cheap.
struct AuroraBackground: View {
    let tint: Color
    /// 0...~1: how strongly the colour shows (dim when nothing is playing).
    let strength: Double

    var body: some View {
        let warm = Theme.shifted(tint, hueDegrees: 60)
        let cool = Theme.shifted(tint, hueDegrees: -50)
        // The drift is about 2 pt a second, so a slow timeline looks identical to a 60 fps animation.
        TimelineView(.animation(minimumInterval: 1.0 / 10)) { context in
            // -1...1 and back every 28 s (14 s each way).
            let drift = sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 28)
            ZStack(alignment: .topLeading) {
                Theme.background
                RadialGradient(
                    colors: [tint.opacity(0.36 * strength), tint.opacity(0.08 * strength), .clear],
                    center: UnitPoint(x: 0.5, y: 0.04),
                    startRadius: 4,
                    endRadius: 340
                )
                blob(warm, opacity: 0.5 * strength, size: 250)
                    .offset(x: -64 + 14 * drift, y: 160 + 8 * drift)
                blob(cool, opacity: 0.45 * strength, size: 270)
                    .offset(x: 190 - 12 * drift, y: -34 + 10 * drift)
            }
            .animation(.smooth(duration: 1.0), value: tint)
            .animation(.smooth(duration: 0.7), value: strength)
        }
        // Its own Metal layer. Left in the popover's main layer, anything animating here re-rasterises every
        // glyph of the text on top of it on every frame, which shows as the text flickering.
        .drawingGroup()
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}
