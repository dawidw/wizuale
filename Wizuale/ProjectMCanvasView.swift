import GLKit
import SwiftUI
import UIKit

/// Full-screen libprojectM output. Raw preset rendering only — no Metal path, no grading.
struct ProjectMCanvasView: UIViewControllerRepresentable {
    var renderState: ProjectMRenderState
    var audioHub: ProjectMAudioHub
    var micReceiver: MicReceiver
    var paused: Bool
    @Binding var failure: String?

    func makeUIViewController(context: Context) -> ProjectMViewController {
        let controller = ProjectMViewController(renderState: renderState, audioHub: audioHub, micReceiver: micReceiver)
        controller.onFailure = { message in
            DispatchQueue.main.async { failure = message }
        }
        return controller
    }

    func updateUIViewController(_ controller: ProjectMViewController, context: Context) {
        controller.paused = paused
    }
}

final class ProjectMViewController: UIViewController, GLKViewDelegate {
    private let renderState: ProjectMRenderState
    private let audioHub: ProjectMAudioHub
    private let micReceiver: MicReceiver
    private var lastFrameTime: CFTimeInterval = 0
    private let projectM = ProjectMController()
    private var glView: GLKView!
    private var context: EAGLContext!
    private var displayLink: CADisplayLink?
    private var lastIndex = -1

    var paused = false
    var onFailure: ((String) -> Void)?

    init(renderState: ProjectMRenderState, audioHub: ProjectMAudioHub, micReceiver: MicReceiver) {
        self.renderState = renderState
        self.audioHub = audioHub
        self.micReceiver = micReceiver
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
        // The Metal renderer used to call sample() every frame; projectM does not.
        // sample() is what reports mic liveness (the green "Mic" chip) to VisualSession.
        let now = CACurrentMediaTime()
        let dt = lastFrameTime > 0 ? Float(now - lastFrameTime) : 1.0 / 60.0
        lastFrameTime = now
        _ = micReceiver.sample(dt: dt)
        glView.display()
    }

    func glkView(_ view: GLKView, drawIn rect: CGRect) {
        guard !paused, let context else { return }
        EAGLContext.setCurrent(context)
        let snap = renderState.snapshot()
        projectM.setBeatSensitivity(snap.beatSensitivity)
        if snap.targetIndex != lastIndex {
            projectM.loadPreset(index: snap.targetIndex, smooth: lastIndex >= 0)
            lastIndex = snap.targetIndex
        }
        audioHub.feed(projectM: projectM)
        glClearColor(0, 0, 0, 1)
        glClear(UInt32(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        projectM.render()
    }
}
