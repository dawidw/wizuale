import SwiftUI
import UIKit

/// Big start button, whether the TV app has answered, sensitivity, latency, and a preset strip.
struct MicRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var mic = MicCapture()
    @State private var dropPressing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WIZUALE MIC")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(2.0)
                            .foregroundStyle(.white.opacity(0.55))

                        HStack(alignment: .center, spacing: 8) {
                            if mic.running {
                                Circle()
                                    .fill(mic.linked ? Color.green : Color.white.opacity(0.28))
                                    .frame(width: 9, height: 9)
                            }
                            Text(headline)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }

                        Text(mic.status)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)

                        meter(title: "Level", value: mic.level)
                        meter(title: "Bass", value: mic.bassLevel)
                        sensitivitySlider
                        latencySlider
                        autoCycleControls
                        calibrateControl
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    IdlePresetStrip(
                        active: mic.activePreset,
                        cycling: mic.cycling,
                        known: mic.pictureKnown,
                        onSelect: { mic.selectPreset($0) }
                    )
                    .equatable()
                    .padding(.bottom, 12)
                }

                HStack(spacing: 12) {
                    dropButton
                    Button(action: { mic.toggle() }) {
                        Text(mic.running ? "Stop" : "Start")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(mic.running ? Color.white.opacity(0.14) : Color.white)
                            .foregroundStyle(mic.running ? Color.white : Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background(Color.black)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                mic.stop()
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var headline: String {
        if !mic.running { return "Ready" }
        if mic.linked {
            let name = mic.tvName.isEmpty ? "Apple TV" : mic.tvName
            return "Connected to \(name)"
        }
        return "Searching for Apple TV…"
    }

    private var sensitivitySlider: some View {
        TuningSlider(
            title: "SENSITIVITY",
            value: $mic.sensitivity,
            range: MicTuning.sensitivityMin...MicTuning.sensitivityMax,
            step: 0.05,
            readout: { gainText($0) },
            onEditingChanged: { mic.setControlScrubbing($0) }
        )
    }

    private var latencySlider: some View {
        TuningSlider(
            title: "LATENCY",
            value: Binding(
                get: { Double(mic.latencyMs) },
                set: { mic.latencyMs = Int($0.rounded()) }
            ),
            range: Double(MicTuning.latencyMin)...Double(MicTuning.latencyMax),
            step: Double(MicTuning.latencyStep),
            readout: { latencyText(Int($0.rounded())) },
            onEditingChanged: { mic.setControlScrubbing($0) }
        )
    }

    private var autoCycleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AUTO-ADVANCE PRESETS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Toggle("Auto-advance presets", isOn: $mic.autoCycle)
                    .labelsHidden()
                    // A translucent track keeps the white knob visible when on.
                    .tint(.white.opacity(0.4))
                    .scaleEffect(0.75, anchor: .trailing)
                    .frame(height: 24)
            }

            if mic.autoCycle {
                TuningSlider(
                    title: "INTERVAL",
                    value: Binding(
                        get: { Double(mic.cycleSeconds) },
                        set: { mic.cycleSeconds = Int($0.rounded()) }
                    ),
                    range: Double(MicTuning.cycleSecondsMin)...Double(MicTuning.cycleSecondsMax),
                    step: 5,
                    readout: { "\(Int($0.rounded()))s" },
                    onEditingChanged: { mic.setControlScrubbing($0) }
                )
            }
        }
    }

    private var calibrateControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            if mic.calibrating {
                Text("KEEP THE ROOM QUIET")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
                ProgressView(value: mic.calibrateProgress)
                    .tint(.white)
                Text(mic.calibrateMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                Button(action: { mic.calibrate() }) {
                    Text("Calibrate")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.14))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                if !mic.calibrateMessage.isEmpty {
                    Text(mic.calibrateMessage)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var dropButton: some View {
        Text(mic.dropActive ? "Dropping" : "Drop")
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(mic.dropActive ? Color.white : Color.white.opacity(0.14))
            .foregroundStyle(mic.dropActive ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !dropPressing {
                            dropPressing = true
                            mic.setDrop(pressed: true)
                        }
                    }
                    .onEnded { _ in
                        dropPressing = false
                        mic.setDrop(pressed: false)
                    }
            )
    }

    private func gainText(_ value: Float) -> String {
        if abs(value - value.rounded()) < 0.02 {
            return String(format: "%.0f×", value)
        }
        return String(format: "%.2f×", value)
    }

    private func latencyText(_ ms: Int) -> String {
        if ms > 0 { return "+\(ms) ms" }
        return "\(ms) ms"
    }

    private func meter(title: String, value: Float) -> some View {
        let amount = CGFloat(min(max(value, 0), 1))
        return VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.5))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * amount)
                }
            }
            .frame(height: 8)
        }
    }
}


/// Preset cards stay put while a slider or the level meters publish.
/// Rebuilding every thumbnail row on each tick was stalling the thumb.
private struct IdlePresetStrip: View, Equatable {
    var active: Int
    var cycling: Bool
    var known: Bool
    var onSelect: (Int) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.active == rhs.active && lhs.cycling == rhs.cycling && lhs.known == rhs.known
    }

    var body: some View {
        PresetStrip(active: active, cycling: cycling, known: known, onSelect: onSelect)
    }
}

/// Label plus slider. The number and the thumb follow the finger from local
/// state; the model write is coalesced so UserDefaults, UDP, and the rest of
/// the screen are not on the touch callback.
private struct TuningSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>
    let step: V.Stride
    let readout: (V) -> String
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var live: V?
    @State private var commit = SliderCommit<V>()

    private var shown: V { live ?? value }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(readout(shown))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            MiniSlider(value: shown, in: range, step: step) { next in
                commit.write = { value = $0 }
                commit.editingChanged = onEditingChanged
                live = next
                commit.push(next)
            } onEnd: { next in
                commit.write = { value = $0 }
                commit.editingChanged = onEditingChanged
                live = nil
                commit.finish(next)
            }
        }
        .onDisappear {
            guard commit.editing else { return }
            let next = live ?? value
            live = nil
            commit.finish(next)
        }
    }
}

/// Latest finger value, held by reference so a deferred model write sees the
/// current sample rather than a copy of the view struct. The model is not
/// written inside the touch callback.
private final class SliderCommit<V: BinaryFloatingPoint & Equatable> {
    var latest: V?
    var lastSent: V?
    var editing = false
    var armed = false
    var write: ((V) -> Void)?
    var editingChanged: ((Bool) -> Void)?

    deinit {
        guard editing else { return }
        editing = false
        editingChanged?(false)
    }

    func push(_ value: V) {
        latest = value
        if !editing {
            editing = true
            lastSent = nil
            editingChanged?(true)
        }
        guard !armed else { return }
        armed = true
        DispatchQueue.main.async { [weak self] in
            self?.tick()
        }
    }

    func finish(_ value: V) {
        let was = editing
        editing = false
        latest = nil
        lastSent = value
        write?(value)
        if was { editingChanged?(false) }
    }

    private func tick() {
        guard editing, let latest else {
            armed = false
            return
        }
        if lastSent != latest {
            lastSent = latest
            write?(latest)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.032) { [weak self] in
            self?.tick()
        }
    }
}

/// Compact slider: thin track, small white thumb. The system slider on
/// iOS 26 ignores controlSize and its thumb dominates the compact layout.
/// Gutters on both sides are not part of the hit target, so a vertical scroll
/// that starts near the screen edge misses the control.
private struct MiniSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let value: V
    let range: ClosedRange<V>
    let step: V.Stride
    var onDrag: (V) -> Void
    var onEnd: (V) -> Void

    init(
        value: V,
        in range: ClosedRange<V>,
        step: V.Stride,
        onDrag: @escaping (V) -> Void,
        onEnd: @escaping (V) -> Void
    ) {
        self.value = value
        self.range = range
        self.step = step
        self.onDrag = onDrag
        self.onEnd = onEnd
    }

    /// Clear of the screen edge, on top of the screen's own horizontal padding.
    static let edgeGutter: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: Self.edgeGutter)
                .allowsHitTesting(false)
            SliderTrack(fraction: fraction(for: value)) { raw, ended in
                let snapped = value(for: raw)
                if ended {
                    onEnd(snapped)
                } else {
                    onDrag(snapped)
                }
                return fraction(for: snapped)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            Color.clear
                .frame(width: Self.edgeGutter)
                .allowsHitTesting(false)
        }
        .frame(height: 28)
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        onDrag(newValue)
                        onEnd(newValue)
                    }
                ),
                in: range,
                step: step
            )
        }
    }

    private func fraction(for value: V) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let f = Double((value - range.lowerBound) / span)
        return CGFloat(min(max(f, 0), 1))
    }

    private func value(for fraction: CGFloat) -> V {
        let span = range.upperBound - range.lowerBound
        var v = range.lowerBound + V(Double(fraction)) * span
        let st = V(step)
        if st > 0 { v = (v / st).rounded() * st }
        return min(max(v, range.lowerBound), range.upperBound)
    }
}

/// Draws the track on the touch callback, so the thumb is not waiting on a
/// SwiftUI update of the screen around it. A scroll view's pan used to win
/// the gesture and deliver the finger late.
private struct SliderTrack: UIViewRepresentable {
    var fraction: CGFloat
    /// Raw fraction in, display fraction out. `ended` is true on release.
    var onFraction: (CGFloat, Bool) -> CGFloat

    func makeUIView(context: Context) -> SliderTrackView {
        let view = SliderTrackView()
        view.fraction = fraction
        view.onFraction = onFraction
        return view
    }

    func updateUIView(_ uiView: SliderTrackView, context: Context) {
        uiView.onFraction = onFraction
        if !uiView.dragging {
            uiView.fraction = fraction
            uiView.setNeedsLayout()
        }
    }
}

private final class SliderTrackView: UIView {
    var fraction: CGFloat = 0
    var dragging = false
    var onFraction: ((CGFloat, Bool) -> CGFloat)?

    private let track = CALayer()
    private let fill = CALayer()
    private let thumb = CALayer()
    private let thumbSize: CGFloat = 20

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        track.backgroundColor = UIColor.white.withAlphaComponent(0.14).cgColor
        track.cornerRadius = 2
        fill.backgroundColor = UIColor.white.cgColor
        fill.cornerRadius = 2
        thumb.backgroundColor = UIColor.white.cgColor
        thumb.cornerRadius = thumbSize / 2
        thumb.shadowColor = UIColor.black.cgColor
        thumb.shadowOpacity = 0.35
        thumb.shadowRadius = 3
        thumb.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(track)
        layer.addSublayer(fill)
        layer.addSublayer(thumb)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.cancelsTouchesInView = true
        press.delaysTouchesBegan = false
        press.delaysTouchesEnded = false
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) { return nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 28)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        hookScrollView()
    }

    /// A scroll view holds subview touches until it decides the gesture is not
    /// a scroll. Turning that delay off lets this track follow the finger.
    /// Gutters are separate views, so a vertical drag that starts there still scrolls.
    private func hookScrollView() {
        var ancestor = superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                if scroll.delaysContentTouches { scroll.delaysContentTouches = false }
                return
            }
            ancestor = current.superview
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hookScrollView()
        let travel = max(bounds.width - thumbSize, 1)
        let x = min(max(fraction, 0), 1) * travel
        let y = bounds.midY
        track.frame = CGRect(x: 0, y: y - 2, width: bounds.width, height: 4)
        fill.frame = CGRect(x: 0, y: y - 2, width: max(x + thumbSize / 2, 0), height: 4)
        thumb.frame = CGRect(x: x, y: y - thumbSize / 2, width: thumbSize, height: thumbSize)
    }

    @objc private func pressed(_ gesture: UILongPressGestureRecognizer) {
        let travel = max(bounds.width - thumbSize, 1)
        let raw = min(max((gesture.location(in: self).x - thumbSize / 2) / travel, 0), 1)
        switch gesture.state {
        case .began, .changed:
            dragging = true
            fraction = onFraction?(raw, false) ?? raw
            setNeedsLayout()
            layoutIfNeeded()
        case .ended:
            dragging = true
            fraction = onFraction?(raw, true) ?? raw
            setNeedsLayout()
            layoutIfNeeded()
            dragging = false
        case .cancelled, .failed:
            if dragging {
                dragging = false
                _ = onFraction?(fraction, true)
            }
        default:
            break
        }
    }
}
