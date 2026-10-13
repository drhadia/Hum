import CoreGraphics
import Foundation
import simd

/// A small CPU ray-tracer that renders the pod body once: a sphere cut flat at the top and bottom,
/// covered in a woven diamond mesh that bends with the surface, lit from the upper left.
/// The lit touch surface is drawn on top by SwiftUI so it can animate.
enum PodRenderer {
    typealias V3 = SIMD3<Float>

    // Geometry, in units of the sphere's radius.
    private static let elevation: Float = 12 * .pi / 180   // camera looks slightly down on the pod
    private static let yTop: Float = 0.835                  // flat top
    private static let yBottom: Float = -0.907              // flat base
    private static let baseY: Float = -0.855                // below this the surface is the smooth base
    private static let glassR: Float = 0.455                // the touch surface
    private static let grooveR: Float = 0.488               // dark gap between glass and woven rim
    private static let cells: Float = 70                    // weave cells around the equator

    private static var topR: Float { (1 - yTop * yTop).squareRoot() }
    private static var sMax: Float { yTop * cos(elevation) + topR * sin(elevation) }

    // MARK: Layout the SwiftUI overlay needs (fractions of the image)

    /// Height / width of the rendered image.
    static var aspect: CGFloat { CGFloat((sMax - bottomExtent) / 2) }
    /// Vertical centre of the touch surface, as a fraction of the image height.
    static var touchCenterY: CGFloat { CGFloat((sMax - yTop * cos(elevation)) / (sMax - bottomExtent)) }
    /// Touch surface width as a fraction of the image width.
    static var touchWidth: CGFloat { CGFloat(glassR) / 1 }
    /// Touch surface height as a fraction of the image height.
    static var touchHeight: CGFloat { CGFloat(2 * glassR * sin(elevation) / (sMax - bottomExtent)) }

    private static var bottomExtent: Float {
        yBottom * cos(elevation) - (1 - yBottom * yBottom).squareRoot() * sin(elevation)
    }

    // MARK: Render

    static let image: CGImage = render(width: 720)

    private static func render(width W: Int) -> CGImage {
        let lo = bottomExtent, hi = sMax
        let H = Int((Float(W) * (hi - lo) / 2).rounded())
        var pixels = [UInt8](repeating: 0, count: W * H * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: H) { j in
                for i in 0..<W {
                    var acc = V3(0, 0, 0)
                    var coverage: Float = 0
                    for sj in 0..<2 {
                        for si in 0..<2 {
                            let sx = (Float(i) + (Float(si) + 0.5) / 2) / Float(W) * 2 - 1
                            let sy = hi - (Float(j) + (Float(sj) + 0.5) / 2) / Float(H) * (hi - lo)
                            if let c = shade(sx, sy) { acc += c; coverage += 1 }
                        }
                    }
                    // Premultiplied: misses contribute no colour, so edges blend correctly.
                    let o = (j * W + i) * 4
                    base[o] = UInt8(max(0, min(255, acc.x / 4 * 255)))
                    base[o + 1] = UInt8(max(0, min(255, acc.y / 4 * 255)))
                    base[o + 2] = UInt8(max(0, min(255, acc.z / 4 * 255)))
                    base[o + 3] = UInt8(coverage / 4 * 255)
                }
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: W, height: H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )!
    }

    // MARK: Ray casting

    private static func shade(_ sx: Float, _ sy: Float) -> V3? {
        let c = cos(elevation), s = sin(elevation)
        let view = V3(0, s, c)                       // from the pod toward the camera
        let origin = V3(sx, sy * c, -sy * s) + view * 5
        let dir = -view

        var hitT: Float?
        var onTop = false
        let b = dot(origin, dir)
        let disc = b * b - (dot(origin, origin) - 1)
        if disc > 0 {
            let t = -b - disc.squareRoot()
            let p = origin + dir * t
            if p.y <= yTop && p.y >= yBottom { hitT = t }
        }
        let tTop = (yTop - origin.y) / dir.y
        let q = origin + dir * tTop
        if q.x * q.x + q.z * q.z <= topR * topR, hitT == nil || tTop < hitT! {
            hitT = tTop
            onTop = true
        }
        guard let t = hitT else { return nil }
        let p = origin + dir * t
        return onTop ? shadeTop(p, view) : shadeSphere(p, view)
    }

    // MARK: Weave

    /// Height of the woven mesh: crossing diagonal threads with a dark diamond hole between them.
    private static func weave(_ u: Float, _ v: Float) -> Float {
        let a = u + v, b = u - v
        let ta = 0.5 + 0.5 * cos(2 * .pi * a)
        let tb = 0.5 + 0.5 * cos(2 * .pi * b)
        let m = (ta + tb) / 2 + ((ta - tb) * (ta - tb) + 0.03).squareRoot() / 2
        return min(1, m * 0.96)
    }

    private static func weaveWithSlope(_ u: Float, _ v: Float) -> (h: Float, du: Float, dv: Float) {
        let e: Float = 0.02
        let h = weave(u, v)
        return (h, (weave(u + e, v) - weave(u - e, v)) / (2 * e), (weave(u, v + e) - weave(u, v - e)) / (2 * e))
    }

    private static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    // MARK: Surfaces

    private static func shadeSphere(_ p: V3, _ view: V3) -> V3 {
        let n = p
        if p.y < baseY { return shadeBase(n, p, view) }
        let phi = asin(p.y), lam = atan2(p.x, p.z)
        // u runs around the pod and shrinks toward the top, v runs up it, so the cells stay square
        // on the surface and the lattice converges the way a real woven shell does.
        let u = lam / (2 * .pi) * cells * cos(phi)
        let v = phi / (2 * .pi) * cells
        let w = weaveWithSlope(u, v)
        let east = V3(cos(lam), 0, -sin(lam))
        let north = V3(-sin(lam) * sin(phi), cos(phi), -cos(lam) * sin(phi))
        let nn = simd_normalize(n - 0.10 * (w.du * east + w.dv * north))
        let ao = 0.42 + 0.58 * smooth(-0.88, -0.15, p.y)   // contact shadow near the table
        return light(nn, n, view, h: w.h, ao: ao)
    }

    private static func shadeBase(_ n: V3, _ p: V3, _ view: V3) -> V3 {
        let key = simd_normalize(V3(-0.5, 0.62, 0.6))
        let d = max(dot(n, key), 0)
        let h = simd_normalize(key + view)
        let spec = pow(max(dot(n, h), 0), 30) * 0.18
        let albedo = V3(0.06, 0.13, 0.23)
        return albedo * (0.35 + 0.7 * d) * 0.55 + V3(0.5, 0.65, 0.9) * spec
    }

    private static func shadeTop(_ p: V3, _ view: V3) -> V3 {
        let r = (p.x * p.x + p.z * p.z).squareRoot()
        let n = V3(0, 1, 0)
        if r < glassR {
            // dark glass; the lit surface is drawn on top of this
            let sheen = smooth(-0.35, 0.45, -p.z * 0.6 + p.x * 0.4)
            return V3(0.018, 0.022, 0.034) + V3(0.05, 0.06, 0.09) * sheen * 0.6
        }
        if r < grooveR { return V3(0.006, 0.012, 0.026) }
        // woven rim
        let ang = atan2(p.x, p.z)
        let u = ang / (2 * .pi) * cells * 0.58
        let v = r * cells / (2 * .pi) * 0.9
        let w = weaveWithSlope(u, v)
        let radial = V3(p.x, 0, p.z) / r
        let tangent = V3(p.z, 0, -p.x) / r
        let nn = simd_normalize(n - 0.16 * (w.du * tangent + w.dv * radial))
        var col = light(nn, n, view, h: w.h, ao: 1)
        // the outer lip catches the light
        col += V3(0.22, 0.42, 0.7) * smooth(0.525, 0.55, r) * 0.5
        return col
    }

    // MARK: Lighting

    private static func light(_ nn: V3, _ n: V3, _ view: V3, h: Float, ao: Float) -> V3 {
        let key = simd_normalize(V3(-0.5, 0.62, 0.6))
        let fill = simd_normalize(V3(0.85, 0.15, -0.25))
        let thread = V3(0.15, 0.33, 0.52)
        let hole = V3(0.025, 0.06, 0.125)
        let t = smooth(0.10, 0.92, h)
        let albedo = hole + (thread - hole) * t

        let micro = max(dot(nn, key), 0)
        let macro = max(dot(n, key), 0)
        let diffuse = 0.26 + 0.10 * n.y + 0.42 * micro + 0.62 * macro
        let fillLight = max(dot(nn, fill), 0) * 0.32
        let halfway = simd_normalize(key + view)
        let spec = pow(max(dot(nn, halfway), 0), 30) * 0.30 * t
        let fresnel = pow(1 - max(dot(n, view), 0), 3.2) * 0.30
        let cavity = 0.62 + 0.38 * t

        var c = albedo * diffuse * cavity * ao
        c += albedo * V3(0.3, 0.55, 1.0) * fillLight * 1.3 * ao
        c += V3(0.75, 0.88, 1.0) * spec * ao
        c += V3(0.2, 0.45, 0.85) * fresnel * (0.4 + 0.6 * t) * ao
        return simd_clamp(c, V3(repeating: 0), V3(repeating: 1))
    }
}
