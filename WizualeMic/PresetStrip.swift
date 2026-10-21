import simd
import SwiftUI

/// Horizontal preset picker. `choice` is `-1` for auto, otherwise an index into `PresetLibrary.all`.
struct PresetStrip: View {
    var active: Int
    var cycling: Bool
    var known: Bool
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESETS")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 28)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        PresetCard(
                            title: "Auto",
                            mode: nil,
                            params: nil,
                            selected: known && cycling
                        ) {
                            onSelect(Int(PresetWire.auto))
                        }
                        .id(Int(PresetWire.auto))
                        ForEach(Array(PresetLibrary.all.enumerated()), id: \.offset) { offset, preset in
                            PresetCard(
                                title: preset.name,
                                mode: preset.mode,
                                params: preset.params,
                                selected: known && offset == active && !cycling,
                                playing: known && offset == active
                            ) {
                                onSelect(offset)
                            }
                            .id(offset)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 2)
                }
                .onAppear {
                    proxy.scrollTo(active, anchor: .center)
                }
                .onChange(of: active) { _, value in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
                .onChange(of: cycling) { _, _ in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(active, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct PresetCard: View {
    var title: String
    var mode: VisualMode?
    var params: PresetParams?
    var selected: Bool
    var playing: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                PresetArtwork(mode: mode, params: params)
                    .frame(width: 116, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ring, lineWidth: selected ? 2.5 : 1.5)
                    }
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(selected || playing ? 0.95 : 0.62))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 116, height: 32, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
    }

    private var ring: Color {
        if selected { return .white }
        if playing { return .white.opacity(0.72) }
        return .white.opacity(0.16)
    }
}

/// Static thumbnail. The marks are deterministic so the card does not flicker.
private struct PresetArtwork: View {
    var mode: VisualMode?
    var params: PresetParams?

    var body: some View {
        let shown = mode
        let look = params
        return Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let base = Self.rgb(look?.base ?? SIMD3(0.02, 0.02, 0.03), floor: 0.03)
            let c0 = Self.rgb(look?.color0 ?? SIMD3(0.55, 0.85, 1))
            let c1 = Self.rgb(look?.color1 ?? SIMD3(1, 0.45, 0.75))
            let c2 = Self.rgb(look?.color2 ?? SIMD3(1, 0.85, 0.35))
            context.fill(Path(bounds), with: .color(base))
            Self.draw(shown, in: bounds, context: &context, c0: c0, c1: c1, c2: c2)
        }
    }

    private static func draw(_ mode: VisualMode?, in bounds: CGRect, context: inout GraphicsContext, c0: Color, c1: Color, c2: Color) {
        let w = bounds.width
        let h = bounds.height
        let mid = CGPoint(x: w * 0.5, y: h * 0.5)
        switch mode {
        case nil:
            ring(&context, mid, min(w, h) * 0.28, c0, 3)
            ring(&context, mid, min(w, h) * 0.16, c1, 2)
            var arrow = Path()
            arrow.move(to: CGPoint(x: mid.x + 4, y: mid.y - 10))
            arrow.addLine(to: CGPoint(x: mid.x + 14, y: mid.y))
            arrow.addLine(to: CGPoint(x: mid.x + 4, y: mid.y + 10))
            context.stroke(arrow, with: .color(c2), lineWidth: 2)
        case .tunnelVision:
            for step in 0..<5 {
                let inset = CGFloat(step) * 8 + 6
                let rect = bounds.insetBy(dx: inset, dy: inset * 0.72)
                context.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(step % 2 == 0 ? c0 : c2), lineWidth: 1.5)
            }
        case .plasmaDrift:
            context.fill(Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.18, width: 46, height: 46)), with: .color(c0.opacity(0.8)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.38, y: h * 0.28, width: 42, height: 42)), with: .color(c1.opacity(0.75)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.24, y: h * 0.08, width: 36, height: 36)), with: .color(c2.opacity(0.7)))
        case .spectrumSpiral:
            var path = Path()
            path.move(to: mid)
            for step in 1...48 {
                let t = CGFloat(step) / 48
                let ang = t * .pi * 5.2
                let rad = t * min(w, h) * 0.46
                path.addLine(to: CGPoint(x: mid.x + cos(ang) * rad, y: mid.y + sin(ang) * rad))
            }
            context.stroke(path, with: .color(c0), lineWidth: 2)
        case .kaleidoBass:
            var left = Path()
            left.move(to: CGPoint(x: 10, y: h - 10))
            left.addLine(to: CGPoint(x: mid.x - 4, y: h - 10))
            left.addLine(to: CGPoint(x: mid.x - 4, y: 14))
            left.closeSubpath()
            var right = left.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
            context.fill(left, with: .color(c0.opacity(0.9)))
            context.fill(right, with: .color(c1.opacity(0.9)))
        case .starburst:
            for step in 0..<12 {
                let ang = CGFloat(step) / 12 * .pi * 2
                let rad = CGFloat(18 + (step % 3) * 12)
                let dot = CGRect(x: mid.x + cos(ang) * rad - 2, y: mid.y + sin(ang) * rad * 0.72 - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: dot), with: .color(step % 2 == 0 ? c2 : c0))
            }
        case .waveformGlow:
            var path = Path()
            for step in 0...40 {
                let t = CGFloat(step) / 40
                let x = 8 + t * (w - 16)
                let y = mid.y + sin(t * .pi * 5) * 14 + cos(t * .pi * 2.5) * 5
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(c0), lineWidth: 2)
            ring(&context, mid, min(w, h) * 0.22, c1, 1.5)
        case .liquidMirror:
            wave(&context, bounds, color: c0, amp: 10, phase: 0, width: 3)
            wave(&context, bounds, color: c1, amp: 7, phase: 1.4, width: 2)
        case .electricSheep:
            for step in 0..<10 {
                let ang = CGFloat(step) / 10 * .pi * 2
                let rad = CGFloat(12 + (step % 4) * 8)
                let dot = CGRect(x: mid.x + cos(ang) * rad - 2, y: mid.y + sin(ang) * rad - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: dot), with: .color(step % 2 == 0 ? c1 : c2))
            }
        case .fractalTunnel:
            for step in 0..<5 {
                ring(&context, mid, CGFloat(8 + step * 7), step % 2 == 0 ? c0 : c1, 1.5)
            }
        case .spectrumBars:
            for step in 0..<8 {
                let x = 12 + CGFloat(step) * (w - 24) / 7
                let barH = 12 + CGFloat((step * 3) % 7) * 5
                context.fill(Path(CGRect(x: x, y: h - 10 - barH, width: 8, height: barH)), with: .color(step % 2 == 0 ? c0 : c1))
            }
        case .vortexPulse:
            var path = Path()
            for step in 0...56 {
                let t = CGFloat(step) / 56
                let ang = t * .pi * 7
                let rad = (1 - t) * min(w, h) * 0.46
                let point = CGPoint(x: mid.x + cos(ang) * rad, y: mid.y + sin(ang) * rad)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(c1), lineWidth: 2)
        case .hueWheel:
            for step in 0..<8 {
                let ang = CGFloat(step) / 8 * .pi * 2
                var spoke = Path()
                spoke.move(to: mid)
                spoke.addLine(to: CGPoint(x: mid.x + cos(ang) * w * 0.42, y: mid.y + sin(ang) * h * 0.42))
                context.stroke(spoke, with: .color(step % 2 == 0 ? c0 : c1), lineWidth: 2)
            }
        }
    }

    private static func ring(_ context: inout GraphicsContext, _ center: CGPoint, _ radius: CGFloat, _ color: Color, _ width: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: width)
    }

    private static func band(_ context: inout GraphicsContext, _ bounds: CGRect, y: CGFloat, color: Color, height: CGFloat) {
        let rect = CGRect(x: 0, y: y, width: bounds.width, height: height)
        context.fill(Path(rect), with: .color(color.opacity(0.85)))
    }

    private static func wave(_ context: inout GraphicsContext, _ bounds: CGRect, color: Color, amp: CGFloat, phase: CGFloat, width: CGFloat) {
        var path = Path()
        let midY = bounds.height * 0.5
        for step in 0...28 {
            let t = CGFloat(step) / 28
            let x = t * bounds.width
            let y = midY + sin(t * .pi * 2 + phase) * amp
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    private static func rgb(_ value: SIMD3<Float>, floor: Float = 0) -> Color {
        let red = Double(min(max(value.x, floor), 1))
        let green = Double(min(max(value.y, floor), 1))
        let blue = Double(min(max(value.z, floor), 1))
        return Color(red: red, green: green, blue: blue)
    }
}
