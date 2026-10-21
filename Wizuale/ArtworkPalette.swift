import simd
import UIKit

/// Three saturated mid-tones from album art. Near-white, pastel, near-black,
/// and grey pixels are skipped. What remains is pushed toward a real hue and
/// kept around 0.6–0.7 brightness, so a light cover cannot wash the picture out.
/// The preset's own dark background is never replaced. Nil means the cover had
/// no usable color and the preset palette should stay.
enum ArtworkPalette {
    static func extract(from image: UIImage) -> AlbumColors? {
        let side = 40
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        guard let cgImage = image.cgImage ?? rasterized(image) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let binCount = 18
        var weight = [Float](repeating: 0, count: binCount)
        var red = [Float](repeating: 0, count: binCount)
        var green = [Float](repeating: 0, count: binCount)
        var blue = [Float](repeating: 0, count: binCount)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Float(pixels[index + 3]) / 255
            guard alpha > 0.04 else { continue }
            var r = Float(pixels[index]) / 255 / alpha
            var g = Float(pixels[index + 1]) / 255 / alpha
            var b = Float(pixels[index + 2]) / 255 / alpha
            r = min(max(r, 0), 1)
            g = min(max(g, 0), 1)
            b = min(max(b, 0), 1)
            let (hue, saturation, value) = hsv(r, g, b)
            let darkest = min(r, min(g, b))
            // Near-black, grey, pastel sky, and white fur do not vote.
            if value < 0.18 || saturation < 0.34 { continue }
            if darkest > 0.70 { continue }
            if value > 0.78 { continue }
            let sample = saturation * value
            let bin = min(binCount - 1, Int(hue * Float(binCount)))
            weight[bin] += sample
            red[bin] += r * sample
            green[bin] += g * sample
            blue[bin] += b * sample
        }

        let ranked = (0..<binCount)
            .filter { weight[$0] > 8 }
            .sorted { weight[$0] > weight[$1] }

        var picked: [SIMD3<Float>] = []
        var used: [Int] = []
        for bin in ranked {
            let crowded = used.contains { circularDistance($0, bin, binCount) < 2 }
            if crowded { continue }
            let amount = max(weight[bin], 0.0001)
            picked.append(tame(SIMD3(red[bin] / amount, green[bin] / amount, blue[bin] / amount)))
            used.append(bin)
            if picked.count == 3 { break }
        }

        guard let first = picked.first else { return nil }
        if picked.count == 1 {
            picked.append(shiftHue(first, by: 0.18))
            picked.append(shiftHue(first, by: -0.18))
        } else if picked.count == 2 {
            picked.append(shiftHue(first, by: 0.18))
        }
        return AlbumColors(first: picked[0], second: picked[1], third: picked[2])
    }

    private static func rasterized(_ image: UIImage) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40), format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 40, height: 40))
        }.cgImage
    }

    private static func hsv(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let maxValue = max(r, max(g, b))
        let minValue = min(r, min(g, b))
        let delta = maxValue - minValue
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        var hue: Float = 0
        if delta > 0.0001 {
            if maxValue == r {
                hue = (g - b) / delta + (g < b ? 6 : 0)
            } else if maxValue == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue /= 6
        }
        return (hue, saturation, maxValue)
    }

    private static func hsvToRGB(_ h: Float, _ s: Float, _ v: Float) -> SIMD3<Float> {
        let sector = Int(h * 6)
        let fraction = h * 6 - Float(sector)
        let p = v * (1 - s)
        let q = v * (1 - fraction * s)
        let t = v * (1 - (1 - fraction) * s)
        switch sector % 6 {
        case 0: return SIMD3(v, t, p)
        case 1: return SIMD3(q, v, p)
        case 2: return SIMD3(p, v, t)
        case 3: return SIMD3(p, q, v)
        case 4: return SIMD3(t, p, v)
        default: return SIMD3(v, p, q)
        }
    }

    private static func shiftHue(_ color: SIMD3<Float>, by amount: Float) -> SIMD3<Float> {
        var (hue, saturation, value) = hsv(color.x, color.y, color.z)
        hue += amount
        hue -= floor(hue)
        return tame(hsvToRGB(hue, saturation, value))
    }

    /// More chroma, and value held in the mid-tones, so strokes stay colored
    /// and the dark background is left alone.
    private static func tame(_ color: SIMD3<Float>) -> SIMD3<Float> {
        var (hue, saturation, value) = hsv(color.x, color.y, color.z)
        saturation = min(1, max(saturation * 1.65, 0.64))
        value = min(max(value, 0.34), 0.68)
        let rgb = hsvToRGB(hue, saturation, value)
        return SIMD3(min(rgb.x, 0.70), min(rgb.y, 0.70), min(rgb.z, 0.70))
    }

    private static func circularDistance(_ a: Int, _ b: Int, _ count: Int) -> Int {
        let delta = abs(a - b) % count
        return min(delta, count - delta)
    }
}
