import GLKit
import SwiftUI
import UIKit

/// Full-screen libprojectM output. Raw preset rendering only — no Metal path, no grading.
struct ProjectMCanvasView: UIViewControllerRepresentable {
    var renderState: ProjectMRenderState
    var audioHub: ProjectMAudioHub
    var paused: Bool
    @Binding var failure: String?

    func makeUIViewController(context: Context) -> ProjectMViewController {
        let controller = ProjectMViewController(renderState: renderState, audioHub: audioHub)
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
    private let projectM = ProjectMController()
    private var glView: GLKView!
    private var context: EAGLContext!
    private var displayLink: CADisplayLink?
    private var lastIndex = -1

    var paused = false
    var onFailure: ((String) -> Void)?

    init(renderState: ProjectMRenderState, audioHub: ProjectMAudioHub) {
        self.renderState = renderState
        self.audioHub = audioHub
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
        projectM.create(in: ctx, size: view.bounds.size)
        if !projectM.isReady {
            onFailure?("libprojectM did not start. Run scripts/build-projectm-tvos.sh on a Mac.")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        EAGLContext.setCurrent(context)
        projectM.resize(view.bounds.size)
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

    @objc private func tick() {
        glView.setNeedsDisplay()
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
