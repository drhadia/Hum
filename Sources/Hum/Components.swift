import SwiftUI

// MARK: - Vertical volume slider

/// A tall pill that fills from the bottom with the volume. Drag anywhere on it.
struct VerticalVolumeSlider: View {
    let value: Float
    let cap: Float
    let tint: Color
    let onChange: (Float) -> Void

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fill = max(CGFloat(value) * h, 4)
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.07))
                LinearGradient(colors: [tint.opacity(0.38), tint.opacity(0.92)], startPoint: .bottom, endPoint: .top)
                    .frame(height: fill)
                    .shadow(color: tint.opacity(dragging ? 0.75 : 0.5), radius: 12)
                if cap < 1 {
                    // Marks where the volume limit stops.
                    Rectangle()
                        .fill(Color.white.opacity(0.32))
                        .frame(height: 1.5)
                        .offset(y: -(CGFloat(cap) * h - 0.75))
                }
                Capsule()
                    .fill(Color.white)
                    .frame(width: dragging ? 24 : 20, height: 4)
                    .shadow(color: .white.opacity(0.8), radius: 5)
                    .offset(y: -(fill - 2))
            }
            .clipShape(Capsule())
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragging = true
                        onChange(Float(1 - min(max(drag.location.y / h, 0), 1)))
                    }
                    .onEnded { _ in dragging = false }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
            .animation(.smooth(duration: 0.6), value: tint)
        }
    }
}

// MARK: - Dock

/// One slot in the bottom dock: a glyph, a small label and a value. Lifts and grows under the cursor.
struct DockItem<Icon: View>: View {
    let title: String
    let value: String
    @ViewBuilder var icon: () -> Icon

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            icon().frame(height: 18)
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(hovering ? Color.white.opacity(0.10) : .clear))
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .scaleEffect(hovering ? 1.1 : 1)
        .offset(y: hovering ? -5 : 0)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: hovering)
    }
}

func dockGlyph(_ name: String, color: Color = .white.opacity(0.82)) -> some View {
    Image(systemName: name)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(color)
}

// MARK: - Track title

/// The song title set large: the last word in the track's colour gradient. Long titles step down in size.
struct TrackTitle: View {
    let title: String
    let tint: Color

    var body: some View {
        let words = title.split(separator: " ").map(String.init)
        let lead = words.count > 1 ? words.dropLast().joined(separator: " ") : nil
        let tail = words.last ?? title
        let size: CGFloat = title.count > 26 ? 24 : (title.count > 16 ? 30 : 35)
        VStack(alignment: .leading, spacing: 0) {
            if let lead {
                Text(lead)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            Text(tail)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.shifted(tint, hueDegrees: 0, saturation: 0.55, brightness: 1), Theme.shifted(tint, hueDegrees: 60, saturation: 0.55, brightness: 1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .font(.system(size: size, weight: .bold))
        .tracking(-size * 0.04)
        .frame(width: 196, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
