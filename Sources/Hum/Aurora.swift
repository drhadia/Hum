import SwiftUI

/// The popover's atmosphere: a glow from the top in the track's colour, and two soft blobs in
/// neighbouring hues that drift slowly. Built from gradients (no blur filters) so it stays cheap.
struct AuroraBackground: View {
    let tint: Color
    /// 0...~1: how strongly the colour shows (dim when nothing is playing).
    let strength: Double

    @State private var drift = false

    var body: some View {
        let warm = Theme.shifted(tint, hueDegrees: 60)
        let cool = Theme.shifted(tint, hueDegrees: -50)
        ZStack(alignment: .topLeading) {
            Theme.background
            RadialGradient(
                colors: [tint.opacity(0.36 * strength), tint.opacity(0.08 * strength), .clear],
                center: UnitPoint(x: 0.5, y: 0.04),
                startRadius: 4,
                endRadius: 340
            )
            blob(warm, opacity: 0.5 * strength, size: 250)
                .offset(x: -64 + (drift ? 14 : -14), y: 160 + (drift ? 8 : -8))
            blob(cool, opacity: 0.45 * strength, size: 270)
                .offset(x: 190 + (drift ? -12 : 12), y: -34 + (drift ? 10 : -10))
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 1.0), value: tint)
        .animation(.smooth(duration: 0.7), value: strength)
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func blob(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}
