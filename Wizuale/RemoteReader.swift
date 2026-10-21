import SwiftUI
import UIKit

/// Siri Remote. Swipe changes the picture, click steps forward, a hold pins
/// the title, play/pause controls Music. Menu is forwarded so the app can exit.
struct RemoteReader: UIViewControllerRepresentable {
    var onLeft: () -> Void
    var onRight: () -> Void
    var onSelect: () -> Void
    var onLongPress: () -> Void
    var onPlayPause: () -> Void

    func makeUIViewController(context: Context) -> RemoteController {
        let controller = RemoteController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: RemoteController, context: Context) {
        controller.remote.onLeft = onLeft
        controller.remote.onRight = onRight
        controller.remote.onSelect = onSelect
        controller.remote.onLongPress = onLongPress
        controller.remote.onPlayPause = onPlayPause
    }

    final class RemoteController: UIViewController {
        let remote = RemoteView()

        override func loadView() {
            view = remote
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }

        override var preferredFocusEnvironments: [UIFocusEnvironment] {
            [remote]
        }
    }

    final class RemoteView: UIView {
        var onLeft: () -> Void = {}
        var onRight: () -> Void = {}
        var onSelect: () -> Void = {}
        var onLongPress: () -> Void = {}
        var onPlayPause: () -> Void = {}

        private var selectBegan: Date?
        private let holdThreshold: TimeInterval = 0.55

        override var canBecomeFocused: Bool { true }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = true
            isAccessibilityElement = true
            accessibilityLabel = "Wizuale"
            accessibilityHint = "Swipe left or right to change the picture. Click to step forward. Hold to pin the title."
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("RemoteView is created in code.")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var forwarded = false
            for press in presses {
                switch press.type {
                case .select:
                    selectBegan = Date()
                case .leftArrow:
                    onLeft()
                case .rightArrow:
                    onRight()
                case .playPause:
                    onPlayPause()
                case .menu:
                    forwarded = true
                default:
                    forwarded = true
                }
            }
            if forwarded {
                super.pressesBegan(presses, with: event)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var forwarded = false
            for press in presses {
                switch press.type {
                case .select:
                    let began = selectBegan ?? Date()
                    selectBegan = nil
                    if Date().timeIntervalSince(began) >= holdThreshold {
                        onLongPress()
                    } else {
                        onSelect()
                    }
                case .menu:
                    forwarded = true
                default:
                    break
                }
            }
            if forwarded {
                super.pressesEnded(presses, with: event)
            }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            selectBegan = nil
            super.pressesCancelled(presses, with: event)
        }
    }
}
