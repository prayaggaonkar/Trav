import SceneKit
import SwiftUI

struct EarthGlobeView: UIViewRepresentable {
    let controller: EarthGlobeController

    func makeUIView(context: Context) -> GlobeSCNView {
        let view = GlobeSCNView(frame: .zero, options: [:])
        configureOnce(view)
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: GlobeSCNView, context: Context) {
        uiView.scene = controller.renderer.scene
        uiView.pointOfView = controller.renderer.cameraNode
    }

    private func configureOnce(_ view: GlobeSCNView) {
        view.scene = controller.renderer.scene
        view.pointOfView = controller.renderer.cameraNode
        view.backgroundColor = .clear
        view.isOpaque = false
        view.layer.isOpaque = false
        view.isMultipleTouchEnabled = true
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.rendersContinuously = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let controller: EarthGlobeController
        private weak var view: GlobeSCNView?

        init(controller: EarthGlobeController) {
            self.controller = controller
        }

        func attach(to view: GlobeSCNView) {
            if self.view === view { return }
            self.view?.gestureRecognizers?.forEach { self.view?.removeGestureRecognizer($0) }
            self.view = view
            controller.attach(to: view)

            view.onKeyboardZoom = { [weak self] direction in
                self?.controller.handleKeyboardZoom(direction: direction)
            }

            let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
            view.addGestureRecognizer(tap)

            view.becomeFirstResponder()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        @objc func onPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            controller.handlePan(at: gesture.location(in: view), state: gesture.state)
        }

        @objc func onPinch(_ gesture: UIPinchGestureRecognizer) {
            controller.handlePinch(scale: gesture.scale, state: gesture.state)
        }

        @objc func onTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? GlobeSCNView else { return }
            view.becomeFirstResponder()
            controller.handleTap(at: gesture.location(in: view))
        }
    }
}

/// SCNView with keyboard and scroll-wheel zoom for Simulator testing.
final class GlobeSCNView: SCNView {
    var onKeyboardZoom: ((Int) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "+", modifierFlags: [], action: #selector(zoomIn)),
            UIKeyCommand(input: "=", modifierFlags: [], action: #selector(zoomIn)),
            UIKeyCommand(input: "-", modifierFlags: [], action: #selector(zoomOut)),
            UIKeyCommand(
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                action: #selector(zoomIn)
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                action: #selector(zoomOut)
            ),
        ]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            switch key.charactersIgnoringModifiers {
            case "+", "=":
                onKeyboardZoom?(1)
                handled = true
            case "-":
                onKeyboardZoom?(-1)
                handled = true
            default:
                break
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    @objc private func zoomIn() {
        onKeyboardZoom?(1)
    }

    @objc private func zoomOut() {
        onKeyboardZoom?(-1)
    }
}
