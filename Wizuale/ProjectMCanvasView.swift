import GLKit
import SwiftUI
import UIKit

/// Full-screen libprojectM output. Raw preset rendering only — no Metal path, no grading.
struct ProjectMCanvasView: UIViewControllerRepresentable {
    var renderState: ProjectMRenderState
    var audioHub: ProjectMAudioHub
    var micReceiver: MicReceiver
    var micSource: MicInputSource
    var paused: Bool
    var beatPunch: BeatPunchState
    var beatStrength: Int
    var sceneIntensity: Int
    var onAudioFrame: ((MicDrive, ProjectMAudioHub.Metrics, BeatPunchFrame) -> Void)?
    @Binding var failure: String?

    func makeUIViewController(context: Context) -> ProjectMViewController {
        let controller = ProjectMViewController(
            renderState: renderState,
            audioHub: audioHub,
            micReceiver: micReceiver,
            micSource: micSource,
            beatPunch: beatPunch,
            onAudioFrame: onAudioFrame
        )
        controller.onFailure = { message in
            DispatchQueue.main.async { failure = message }
        }
        return controller
    }

    func updateUIViewController(_ controller: ProjectMViewController, context: Context) {
        controller.paused = paused
        controller.micSource = micSource
        controller.beatStrength = beatStrength
        controller.sceneIntensity = sceneIntensity
    }
}

final class ProjectMViewController: UIViewController, GLKViewDelegate {
    private let renderState: ProjectMRenderState
    private let audioHub: ProjectMAudioHub
    private let micReceiver: MicReceiver
    private let beatPunch: BeatPunchState
    private let onAudioFrame: ((MicDrive, ProjectMAudioHub.Metrics, BeatPunchFrame) -> Void)?
    private var lastFrameTime: CFTimeInterval = 0
    private var renderFpsEma: Float = 60
    private let projectM = ProjectMController()
    private var glView: GLKView!
    private var context: EAGLContext!
    private var displayLink: CADisplayLink?
    private var lastIndex = -1

    var paused = false
    var micSource: MicInputSource = .phone
    var beatStrength: Int = MicTuning.loadTVBeatStrength()
    var sceneIntensity: Int = MicTuning.loadTVSceneIntensity()
    var onFailure: ((String) -> Void)?

    init(
        renderState: ProjectMRenderState,
        audioHub: ProjectMAudioHub,
        micReceiver: MicReceiver,
        micSource: MicInputSource,
        beatPunch: BeatPunchState,
        onAudioFrame: ((MicDrive, ProjectMAudioHub.Metrics, BeatPunchFrame) -> Void)?
    ) {
        self.renderState = renderState
        self.audioHub = audioHub
        self.micReceiver = micReceiver
        self.micSource = micSource
        self.beatPunch = beatPunch
        self.onAudioFrame = onAudioFrame
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let ctx = EAGLContext(api: .openGLES3) else {
            onFailure?("OpenGL ES 3 is not available on this Apple TV.")
            return
        }
        context = ctx
        glView = GLKView(frame: view.bounds, context: ctx)
        glView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        glView.drawableColorFormat = .RGBA8888
        glView.drawableDepthFormat = .format24
        glView.enableSetNeedsDisplay = false
        glView.delegate = self
        glView.backgroundColor = .black
        view.addSubview(glView)

        EAGLContext.setCurrent(ctx)
        projectM.create(in: ctx, size: pixelSize)
        if !projectM.isReady {
            onFailure?("libprojectM did not start. Run scripts/build-projectm-tvos.sh on a Mac.")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        EAGLContext.setCurrent(context)
        projectM.resize(pixelSize)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startDisplayLink()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDisplayLink()
    }

    deinit {
        stopDisplayLink()
        EAGLContext.setCurrent(context)
        projectM.destroy()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private var pixelSize: CGSize {
        let scale = view.window?.screen.scale ?? UIScreen.main.scale
        return CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
    }

    /// enableSetNeedsDisplay is false, so setNeedsDisplay() would be ignored; draw explicitly.
    @objc private func tick() {
        guard !paused else { return }
        glView.display()
    }

    func glkView(_ view: GLKView, drawIn rect: CGRect) {
        guard !paused, let context else { return }
        EAGLContext.setCurrent(context)
        let now = CACurrentMediaTime()
        let dt = lastFrameTime > 0 ? Float(now - lastFrameTime) : Float(1.0 / 60.0)
        lastFrameTime = now
        if dt > 1e-4 {
            let instant = min(max(1 / dt, 24), 120)
            renderFpsEma = renderFpsEma * 0.9 + instant * 0.1
            projectM.setRenderFPS(renderFpsEma)
        }
        let drive = micReceiver.sample(dt: dt)
        beatPunch.setStrengthPercent(beatStrength)
        let punchFrame = beatPunch.advance(drive: drive, dt: dt, now: now)
        let snap = renderState.snapshot()
        let intensity = MicTuning.sceneIntensityMultiplier(sceneIntensity)
        let sceneBoost = punchFrame.sceneEnvelope
            * MicTuning.scenePunchSensitivityBoostBaseline
            * Float(beatStrength) / 100
            * intensity
        let sceneSens = MicTuning.clampSceneBeatSensitivity(base: snap.beatSensitivity, punchBoost: sceneBoost)
        projectM.setBeatSensitivity(sceneSens)
        if snap.targetIndex != lastIndex {
            projectM.loadPreset(index: snap.targetIndex, smooth: lastIndex >= 0)
            lastIndex = snap.targetIndex
        }
        audioHub.feed(
            micSource: micSource,
            scenePunch: punchFrame.sceneEnvelope,
            sceneIntensityPermille: sceneIntensity,
            now: now
        ) { projectM.addPCM(floats: $0) }
        onAudioFrame?(drive, audioHub.metricsSnapshot(), punchFrame)
        glClearColor(0, 0, 0, 1)
        glClear(UInt32(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        projectM.render()
    }
}
