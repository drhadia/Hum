import SwiftUI

// MARK: - Data

struct ClimateReading: Equatable {
    var temperatureC: Double
    var humidity: Double   // percent, 0...100
    var date: Date
}

/// Anything that can supply the HomePod mini's temperature and humidity.
///
/// The mini publishes both readings to HomeKit as an accessory called "HomePodSensor". A Mac app can't
/// read that directly (HomeKit needs a paid developer account, and the accessory is paired to the Home
/// app), so no source is connected yet. Implement this and assign it to `AppModel.climateSource`.
protocol ClimateSource: AnyObject {
    func start(_ onReading: @escaping @MainActor (ClimateReading) -> Void)
}

// MARK: - Comfort colours and words

enum Comfort {
    private static func hue(_ stops: [(x: Double, hue: Double)], at x: Double) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if x <= first.x { return first.hue }
        if x >= last.x { return last.hue }
        for i in 1..<stops.count where x <= stops[i].x {
            let a = stops[i - 1], b = stops[i]
            return a.hue + (b.hue - a.hue) * (x - a.x) / (b.x - a.x)
        }
        return last.hue
    }

    /// Cold blue through comfortable teal to warm amber and hot red.
    static func tempColor(_ c: Double) -> Color {
        let h = hue([(10, 0.60), (18, 0.53), (24, 0.44), (26.5, 0.14), (30, 0.06), (35, 0.0)], at: c)
        return Color(hue: h, saturation: 0.62, brightness: 1)
    }

    /// Dry amber through comfortable cyan to humid blue.
    static func humidityColor(_ rh: Double) -> Color {
        let h = hue([(15, 0.10), (35, 0.49), (55, 0.52), (80, 0.65)], at: rh)
        return Color(hue: h, saturation: 0.6, brightness: 1)
    }

    static func tempLabel(_ c: Double) -> String {
        switch c {
        case ..<16: "Chilly"
        case ..<20: "Cool"
        case ...26: "Comfortable"
        case ...30: "Warm"
        default: "Hot"
        }
    }

    static func humidityLabel(_ rh: Double) -> String {
        switch rh {
        case ..<30: "Dry"
        case ...60: "Comfortable"
        case ...70: "Humid"
        default: "Very humid"
        }
    }
}

// MARK: - Smoothing for canvases

/// Eases a level and a colour toward their targets, so canvas drawing (which SwiftUI can't animate)
/// still moves smoothly when a reading changes. Reference type on purpose: updated while drawing.
final class ClimateSmoother {
    private var level: Double = 0
    private var r: Float = 1, g: Float = 1, b: Float = 1
    private var last: Date?

    func step(level target: Double, color: Color.Resolved, now: Date) -> (level: Double, color: Color) {
        if let last {
            let dt = Float(now.timeIntervalSince(last))
            if dt > 0 {
                let kc = 1 - exp(-dt / 0.35)
                r += (color.red - r) * kc; g += (color.green - g) * kc; b += (color.blue - b) * kc
                level += (target - level) * Double(1 - exp(-dt / 0.45))
            }
        } else {
            level = target; r = color.red; g = color.green; b = color.blue
        }
        last = now
        return (level, Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b)))
    }
}

// MARK: - Shapes

/// A water drop: pointed top, round bottom.
struct DropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = w / 2
        let cy = h - r
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x, y: rect.minY + y) }
        var p = Path()
        p.move(to: pt(w / 2, 0))
        p.addCurve(to: pt(0, cy), control1: pt(w / 2 - r * 0.10, h * 0.30), control2: pt(0, cy - r * 0.95))
        let steps = 48
        for i in 1...steps {
            let t = CGFloat.pi - CGFloat.pi * CGFloat(i) / CGFloat(steps)   // left, through the bottom, to the right
            p.addLine(to: pt(w / 2 + r * cos(t), cy + r * sin(t)))
        }
        p.addCurve(to: pt(w / 2, 0), control1: pt(w, cy - r * 0.95), control2: pt(w / 2 + r * 0.10, h * 0.30))
        p.closeSubpath()
        return p
    }
}

// MARK: - Gauges

/// A 270-degree arc that fills with the temperature, with a glowing dot at its tip.
struct TempGauge: View {
    let reading: ClimateReading?
    var size: CGFloat = 44

    private static let range = 10.0 ... 40.0
    private var progress: Double {
        guard let reading else { return 0 }
        return min(max((reading.temperatureC - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound), 0), 1)
    }
    private var color: Color { reading.map { Comfort.tempColor($0.temperatureC) } ?? .white.opacity(0.3) }

    var body: some View {
        let line: CGFloat = size * 0.095
        let radius = (size - line) / 2
        let angle = Angle.degrees(135 + 270 * progress).radians
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .rotation(.degrees(135))
                .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: line, lineCap: .round))
            Circle()
                .trim(from: 0, to: 0.75 * progress)
                .rotation(.degrees(135))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .shadow(color: color.opacity(reading == nil ? 0 : 0.55), radius: 5)
            if reading != nil {
                Circle()
                    .fill(.white)
                    .frame(width: line * 1.2, height: line * 1.2)
                    .shadow(color: color, radius: 3)
                    .offset(x: CGFloat(cos(angle)) * radius, y: CGFloat(sin(angle)) * radius)
            }
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.8), value: progress)
        .animation(.smooth(duration: 0.8), value: color)
    }
}

/// A water drop that fills with a rolling wave up to the humidity.
struct HumidityDrop: View {
    let reading: ClimateReading?
    var width: CGFloat = 30

    private var level: Double { reading.map { min(max($0.humidity / 100, 0), 1) } ?? 0 }
    private var color: Color { reading.map { Comfort.humidityColor($0.humidity) } ?? .white.opacity(0.3) }

    var body: some View {
        let h = width * 1.35
        ZStack {
            DropShape().fill(Color.white.opacity(0.06))
            WaveFill(level: level, color: color)
                .frame(width: width, height: h)
                .mask(DropShape())
            DropShape()
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.55), color.opacity(0.35), color.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.3
                )
        }
        .frame(width: width, height: h)
    }
}

// MARK: - The strip

/// Temperature and humidity as one ruled strip: a gauge or droplet, a big light number, and a word.
struct ClimateStrip: View {
    let reading: ClimateReading?
    var emptyCaption = "No sensor"
    let fahrenheit: Bool
    let onToggleUnit: () -> Void

    private var tempValue: Double { reading.map { fahrenheit ? $0.temperatureC * 9 / 5 + 32 : $0.temperatureC } ?? 0 }
    private var tempColor: Color { reading.map { Comfort.tempColor($0.temperatureC) } ?? Theme.tertiary }
    private var humColor: Color { reading.map { Comfort.humidityColor($0.humidity) } ?? Theme.tertiary }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleUnit) {
                cell(
                    TempGauge(reading: reading, size: 44),
                    label: "TEMP",
                    value: reading == nil ? "–" : String(format: "%.1f°", tempValue),
                    numeric: tempValue,
                    word: reading.map { Comfort.tempLabel($0.temperatureC) } ?? emptyCaption,
                    color: tempColor
                )
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .help(reading == nil ? "Read from the Home app: needs the Accessibility permission" : "Click to switch °C / °F")

            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1).padding(.vertical, 4)

            cell(
                HumidityDrop(reading: reading, width: 28),
                label: "HUMIDITY",
                value: reading == nil ? "–" : "\(Int(reading!.humidity.rounded()))%",
                numeric: reading?.humidity ?? 0,
                word: reading.map { Comfort.humidityLabel($0.humidity) } ?? emptyCaption,
                color: humColor
            )
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
        .animation(.smooth(duration: 0.7), value: reading?.temperatureC)
        .animation(.smooth(duration: 0.7), value: reading?.humidity)
    }

    private func cell<G: View>(_ glyph: G, label: String, value: String, numeric: Double, word: String, color: Color) -> some View {
        HStack(spacing: 12) {
            glyph
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.secondary)
                Text(value)
                    .font(.system(size: 30, weight: .light))
                    .tracking(-1)
                    .monospacedDigit()
                    .foregroundStyle(reading == nil ? Theme.tertiary : .white)
                    .contentTransition(.numericText(value: numeric))
                Text(word)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(reading == nil ? Theme.tertiary : color.opacity(0.95))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

/// Two overlapping waves rolling across, rising to `level`.
private struct WaveFill: View {
    let level: Double
    let color: Color

    @Environment(\.self) private var environment
    @State private var smoother = ClimateSmoother()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let eased = smoother.step(level: level, color: color.resolve(in: environment), now: context.date)
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                guard eased.level > 0.004 else { return }
                let top = size.height * (1 - eased.level)
                let amp = 2.4 * min(1, eased.level * 10, (1 - eased.level) * 10)
                for layer in 0..<2 {
                    let phase = t * (layer == 0 ? 1.6 : -1.1) + Double(layer) * 1.7
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    var x: CGFloat = 0
                    while x <= size.width + 1 {
                        let y = top + CGFloat(sin(Double(x) / Double(size.width) * 2 * .pi * 1.25 + phase)) * CGFloat(amp)
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 1.5
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                    ctx.fill(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [eased.color.opacity(layer == 0 ? 0.50 : 0.85), eased.color.opacity(layer == 0 ? 0.28 : 0.45)]),
                            startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)
                        )
                    )
                }
            }
        }
    }
}
