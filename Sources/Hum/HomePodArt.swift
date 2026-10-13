import SwiftUI

/// What the animated layers draw this frame: the tint, and how "on" (0...1) and how loud (0...1) the pod is.
struct ArtLook {
    var tint: Color
    var live: Double
    var level: Double
}

/// Eases tint, on/off and level toward their targets, so the canvases (which SwiftUI can't animate for us)
/// still fade smoothly. A reference type on purpose: it's updated while drawing and never drives a redraw.
final class ArtSmoother {
    private var r: Float = 0, g: Float = 0, b: Float = 0
    private var live: Float = 0, level: Float = 0
    private var last: Date?

    func step(tint: Color.Resolved, live target: Bool, level targetLevel: Float, now: Date) -> ArtLook {
        if let last {
            let dt = Float(now.timeIntervalSince(last))
            if dt > 0 {
                func k(_ tau: Float) -> Float { 1 - exp(-dt / tau) }
                r += (tint.red - r) * k(0.3)
                g += (tint.green - g) * k(0.3)
                b += (tint.blue - b) * k(0.3)
                live += ((target ? 1 : 0) - live) * k(0.22)
                level += (targetLevel - level) * k(0.15)
            }
        } else {
            // First frame: start at the target so opening the popover never fades in from nothing.
            r = tint.red; g = tint.green; b = tint.blue
            live = target ? 1 : 0
            level = targetLevel
        }
        last = now
        return ArtLook(tint: Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b)), live: Double(live), level: Double(level))
    }
}

/// The hero: the pod (a static layer), with sound rings behind it and the lit touch surface on top.
/// Both animated layers are fixed-size canvases, so animating never triggers a SwiftUI layout pass or
/// re-uploads the pod image.
struct HomePodArt: View {
    /// 1 = the pod is 96 pt wide.
    var scale: CGFloat = 1
    let isPlaying: Bool
    let isMuted: Bool
    let tint: Color
    let level: Float

    @Environment(\.self) private var environment
    @State private var smoother = ArtSmoother()
    @State private var floatUp = false

    private var live: Bool { isPlaying && !isMuted }
    private var podW: CGFloat { PodBodyView.baseWidth * scale }
    private var podH: CGFloat { PodBodyView.baseHeight * scale }
    private var schedule: AnimationTimelineSchedule { .animation(minimumInterval: live ? 1.0 / 24 : 1.0 / 8) }

    private func look(at date: Date) -> ArtLook {
        smoother.step(tint: tint.resolve(in: environment), live: live, level: level, now: date)
    }

    var body: some View {
        ZStack {
            TimelineView(schedule) { context in
                let look = look(at: context.date)
                Canvas { ctx, size in drawBackdrop(&ctx, size, look, t: context.date.timeIntervalSinceReferenceDate) }
                    .frame(width: 280 * scale, height: 280 * scale)
            }
            .frame(width: podW, height: podH)   // layout stays the pod's size; the canvas draws past it

            ZStack {
                PodBodyView(scale: scale)
                    .opacity(isMuted ? 0.55 : 1)

                TimelineView(schedule) { context in
                    let look = look(at: context.date)
                    let t = context.date.timeIntervalSinceReferenceDate
                    let pulse = 0.5 + 0.5 * sin(t * 2.4)
                    TouchGlowCanvas(
                        scale: scale,
                        colors: TouchGlowCanvas.colors(tint: look.tint, rainbow: false),
                        glow: look.live * (isMuted ? 0 : 0.55 + 0.4 * pulse),
                        pulse: pulse,
                        angle: t * 90,
                        lit: look.live > 0.05 && !isMuted
                    )
                }
            }
            .offset(y: live ? (floatUp ? 1.6 * scale : -1.6 * scale) : 0)
            .animation(live ? .easeInOut(duration: 2.8).repeatForever(autoreverses: true) : .smooth(duration: 0.4), value: floatUp)
            .animation(.smooth(duration: 0.4), value: isMuted)
        }
        .frame(width: podW, height: podH)
        .onAppear { floatUp = live }
        .onChange(of: live) { _, on in floatUp = on }
    }

    /// The colour pool under the pod and the sound rings, drawn around the pod's centre in pod units
    /// (96 wide) and scaled up.
    private func drawBackdrop(_ ctx: inout GraphicsContext, _ size: CGSize, _ look: ArtLook, t: TimeInterval) {
        guard look.live > 0.01 else { return }
        var g = ctx
        g.translateBy(x: size.width / 2, y: size.height / 2 - scale)
        g.scaleBy(x: scale, y: scale)

        // pool of colour on the table
        var pool = g
        pool.translateBy(x: 0, y: 52)
        pool.scaleBy(x: 1, y: 0.36)
        pool.fill(
            Path(ellipseIn: CGRect(x: -80, y: -80, width: 160, height: 160)),
            with: .radialGradient(
                Gradient(colors: [look.tint.opacity(look.live * (0.30 + 0.30 * look.level)), look.tint.opacity(0)]),
                center: .zero, startRadius: 0, endRadius: 80
            )
        )

        // rings
        let reach = 55 + 70 * look.level
        for i in 0..<3 {
            let phase = (t * (0.45 + 0.4 * look.level) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let d = 98 + reach * phase
            g.stroke(
                Path(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d)),
                with: .color(look.tint.opacity(0.34 * (1 - phase) * look.live)),
                lineWidth: 1.2
            )
        }
    }
}
