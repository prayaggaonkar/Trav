import SceneKit
import SwiftUI

struct EarthGlobeView: UIViewRepresentable {
    let controller: EarthGlobeController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [:])
        configure(view)
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: SCNView) {
        view.scene = controller.renderer.scene
        view.pointOfView = controller.renderer.cameraNode
        view.backgroundColor = .black
        view.isOpaque = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.rendersContinuously = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    @MainActor
    final class Coordinator: NSObject {
        private let controller: EarthGlobeController
        private var lastPanPoint: CGPoint = .zero
        private weak var view: SCNView?

        init(controller: EarthGlobeController) {
            self.controller = controller
        }

        func attach(to view: SCNView) {
            if self.view === view { return }
            self.view?.gestureRecognizers?.forEach { self.view?.removeGestureRecognizer($0) }
            self.view = view

            let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
            view.addGestureRecognizer(pinch)

            let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
            view.addGestureRecognizer(tap)
        }

        @objc func onPan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            if gesture.state == .began { lastPanPoint = .zero }
            let delta = CGPoint(x: translation.x - lastPanPoint.x, y: translation.y - lastPanPoint.y)
            controller.handlePan(translation: delta, state: gesture.state)
            lastPanPoint = translation
            if gesture.state == .ended || gesture.state == .cancelled { lastPanPoint = .zero }
        }

        @objc func onPinch(_ gesture: UIPinchGestureRecognizer) {
            controller.handlePinch(scale: gesture.scale, state: gesture.state)
            gesture.scale = 1
        }

        @objc func onTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            controller.handleTap(at: gesture.location(in: view))
        }
    }
}
