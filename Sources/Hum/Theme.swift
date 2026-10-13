import AppKit
import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.060)
    static let card = Color.white.opacity(0.055)
    static let cardHover = Color.white.opacity(0.10)
    static let cardStroke = Color.white.opacity(0.07)
    static let secondary = Color.white.opacity(0.45)
    static let tertiary = Color.white.opacity(0.28)
    static let accent = Color(red: 0.83, green: 0.76, blue: 0.64)
    static let live = Color(red: 0.36, green: 0.82, blue: 0.55)

    /// Each track gets one of these, so the whole popover shifts colour with the music.
    private static let palette: [Color] = [
        Color(hue: 0.62, saturation: 0.65, brightness: 0.98),  // indigo
        Color(hue: 0.77, saturation: 0.55, brightness: 0.98),  // violet
        Color(hue: 0.92, saturation: 0.55, brightness: 1.00),  // pink
        Color(hue: 0.03, saturation: 0.62, brightness: 1.00),  // coral
        Color(hue: 0.09, saturation: 0.70, brightness: 1.00),  // amber
        Color(hue: 0.40, saturation: 0.55, brightness: 0.90),  // green
        Color(hue: 0.51, saturation: 0.60, brightness: 0.95),  // teal
    ]

    static func tint(for key: String?) -> Color {
        guard let key, !key.isEmpty else { return accent }
        // djb2: stable across launches, unlike Hasher.
        let hash = key.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return palette[Int(hash % UInt64(palette.count))]
    }

    /// The same colour with its hue rotated, and optionally a new saturation or brightness.
    static func shifted(_ color: Color, hueDegrees: Double, saturation: Double? = nil, brightness: Double? = nil) -> Color {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        var h: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        ns.getHue(&h, saturation: &sat, brightness: &bri, alpha: &alpha)
        var nh = Double(h) + hueDegrees / 360
        nh -= floor(nh)
        return Color(hue: nh, saturation: saturation ?? Double(sat), brightness: brightness ?? Double(bri))
    }
}

/// Springy press feedback shared by every button.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct RoundIconButton: View {
    let systemName: String
    var size: CGFloat = 30
    var tint: Color = .white.opacity(0.75)
    /// A solid white button (the play button) that glows in this colour.
    var filledGlow: Color?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(filledGlow == nil ? tint : Color(white: 0.04))
                .frame(width: size, height: size)
                .background(Circle().fill(filledGlow != nil ? Color.white : (hovering ? Theme.cardHover : Theme.card)))
                .overlay(Circle().strokeBorder(filledGlow == nil ? Theme.cardStroke : .clear))
                .shadow(color: (filledGlow ?? .clear).opacity(0.5), radius: 12, y: 5)
        }
        .buttonStyle(PressableStyle())
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.smooth(duration: 0.5), value: tint)
    }
}

/// Fades and rises each section in, one after another, when the popover opens.
struct Appear: ViewModifier {
    let on: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 12)
            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.045), value: on)
    }
}

extension View {
    func appear(_ on: Bool, _ index: Int) -> some View { modifier(Appear(on: on, index: index)) }
}
