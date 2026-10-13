import SwiftUI

/// The pod body: the ray-traced fabric sphere (see PodRenderer) and its shadow. Static, so it is
/// drawn once and never re-uploaded while the hero animates.
struct PodBodyView: View {
    var scale: CGFloat = 1

    /// Width of the pod at scale 1; the height follows the rendered image.
    static let baseWidth: CGFloat = 96
    static var baseHeight: CGFloat { baseWidth * PodRenderer.aspect }

    var body: some View {
        Image(decorative: PodRenderer.image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: Self.baseWidth * scale, height: Self.baseHeight * scale)
            .shadow(color: .black.opacity(0.55), radius: 14 * scale, y: 10 * scale)
    }
}

/// The lit touch surface, drawn in one fixed-size canvas: swirling colour, a soft spill onto the rim,
/// a gloss highlight, and the - and + marks. Positioned where the rendered pod's glass is.
struct TouchGlowCanvas: View {
    var scale: CGFloat = 1
    let colors: [Color]
    var glow: Double
    var pulse: Double
    var angle: Double
    var lit: Bool

    static func colors(tint: Color, rainbow: Bool) -> [Color] {
        rainbow
            ? [Color(red: 0.45, green: 0.75, blue: 1), .white, Color(red: 1, green: 0.55, blue: 0.8), Color(red: 0.6, green: 0.5, blue: 1), Color(red: 0.2, green: 0.9, blue: 1), Color(red: 0.45, green: 0.75, blue: 1)]
            : [tint, .white.opacity(0.95), tint, tint.opacity(0.65), tint]
    }

    var body: some View {
        let podW = PodBodyView.baseWidth * scale
        let podH = PodBodyView.baseHeight * scale
        let w = PodRenderer.touchWidth * podW
        let h = PodRenderer.touchHeight * podH
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ellipse = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            let gradient = Gradient(colors: colors)
            let conic = GraphicsContext.Shading.conicGradient(gradient, center: c, angle: .degrees(angle))

            if glow > 0.01 {
                // light spilling onto the rim
                var spill = ctx
                spill.opacity = glow * 0.45
                spill.fill(Path(ellipseIn: ellipse.insetBy(dx: -w * 0.05, dy: -h * 0.16)), with: conic)

                var main = ctx
                main.opacity = glow
                let k = 1 + 0.03 * pulse
                main.fill(
                    Path(ellipseIn: ellipse.insetBy(dx: -w * (k - 1) / 2, dy: -h * (k - 1) / 2)),
                    with: conic
                )
            }

            // gloss
            ctx.fill(
                Path(ellipseIn: ellipse),
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]),
                    startPoint: CGPoint(x: c.x, y: ellipse.minY),
                    endPoint: CGPoint(x: c.x, y: c.y)
                )
            )

            // minus on the left, plus on the right
            let mark = Color.white.opacity(lit ? 0.8 : 0.3)
            let len = 3.6 * scale, thick = 0.7 * scale
            let lx = c.x - w * 0.33, rx = c.x + w * 0.33
            ctx.fill(Path(CGRect(x: lx - len / 2, y: c.y - thick / 2, width: len, height: thick)), with: .color(mark))
            ctx.fill(Path(CGRect(x: rx - len / 2, y: c.y - thick / 2, width: len, height: thick)), with: .color(mark))
            ctx.fill(Path(CGRect(x: rx - thick / 2, y: c.y - len / 2, width: thick, height: len)), with: .color(mark))
        }
        .frame(width: w * 1.3, height: h * 1.8)
        .frame(width: podW, height: podH, alignment: .top)
        .offset(y: PodRenderer.touchCenterY * podH - h * 0.9)
        .allowsHitTesting(false)
    }
}

/// The whole pod, posed statically. Used for the app icon, where nothing animates.
struct HomePodMiniBody: View {
    var scale: CGFloat = 1
    let tint: Color
    var glow: Double
    var pulse: Double
    var angle: Double
    var rainbow = false

    var body: some View {
        ZStack(alignment: .top) {
            PodBodyView(scale: scale)
            TouchGlowCanvas(
                scale: scale,
                colors: TouchGlowCanvas.colors(tint: tint, rainbow: rainbow),
                glow: glow,
                pulse: pulse,
                angle: angle,
                lit: glow > 0.01
            )
        }
        .frame(width: PodBodyView.baseWidth * scale, height: PodBodyView.baseHeight * scale, alignment: .top)
    }
}
