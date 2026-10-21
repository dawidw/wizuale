import MetalKit
import SwiftUI

/// Full-screen Metal view. The coordinator keeps the renderer alive:
/// `MTKView.delegate` is weak, and a released renderer draws nothing.
struct MetalCanvasView: UIViewRepresentable {
    var state: RenderState
    var beatClock: BeatClock
    var paused: Bool
    @Binding var failure: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.isPaused = paused
        view.isUserInteractionEnabled = false
        view.autoResizeDrawable = true

        guard let device = MTLCreateSystemDefaultDevice() else {
            report(RendererError.noDevice.localizedDescription)
            view.isPaused = true
            return view
        }
        view.device = device
        do {
            let renderer = try VisualRenderer(device: device, state: state, beatClock: beatClock)
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            report(error.localizedDescription)
            view.isPaused = true
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        view.isPaused = paused || failure != nil
    }

    private func report(_ message: String) {
        DispatchQueue.main.async {
            failure = message
        }
    }

    final class Coordinator {
        var renderer: VisualRenderer?
    }
}
