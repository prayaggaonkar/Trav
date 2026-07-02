import SceneKit
import simd
import UIKit

/// Manages gesture input, momentum, and idle auto-rotation for the globe.
@MainActor
final class EarthGlobeController: NSObject {
    let renderer: EarthGlobeRenderer

    private weak var sceneView: SCNView?
    private nonisolated(unsafe) var tickTimer: Timer?

    private var lastInteractionTime: CFTimeInterval = 0
    private var isDragging = false
    private var dragAnchorWorld = SIMD3<Float>(0, 0, 1)
    private var lastDragWorld = SIMD3<Float>(0, 0, 1)
    private var momentum = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var pinchStartDistance: Float?

    private let autoRotateSpeed: Float = 0.004
    private let idleDelay: CFTimeInterval = 2.5
    private let friction: Float = 0.94
    private let keyboardZoomFactor: Float = 1.12

    var isAnimatingFlyTo = false

    init(renderer: EarthGlobeRenderer) {
        self.renderer = renderer
        super.init()
        startTickTimer()
    }

    deinit {
        tickTimer?.invalidate()
    }

    func attach(to view: SCNView) {
        sceneView = view
    }

    func handlePan(at location: CGPoint, state: UIGestureRecognizer.State) {
        guard !isAnimatingFlyTo, let sceneView else { return }

        switch state {
        case .began:
            isDragging = true
            momentum = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            dragAnchorWorld = renderer.worldDirectionOnSphere(from: location, in: sceneView)
            lastDragWorld = dragAnchorWorld
            lastInteractionTime = CACurrentMediaTime()

        case .changed:
            guard isDragging else { return }
            let targetWorld = renderer.worldDirectionOnSphere(from: location, in: sceneView)
            renderer.applyDragDelta(from: lastDragWorld, to: targetWorld)
            momentum = renderer.shortestRotationForMomentum(from: lastDragWorld, to: targetWorld)
            lastDragWorld = targetWorld
            lastInteractionTime = CACurrentMediaTime()

        case .ended, .cancelled:
            isDragging = false
            lastInteractionTime = CACurrentMediaTime()

        default:
            break
        }
    }

    func handlePinch(scale: CGFloat, state: UIGestureRecognizer.State) {
        guard !isAnimatingFlyTo else { return }

        switch state {
        case .began:
            pinchStartDistance = renderer.cameraDistance
            lastInteractionTime = CACurrentMediaTime()
        case .changed:
            guard let start = pinchStartDistance else { return }
            renderer.setCameraDistance(start / Float(scale))
            lastInteractionTime = CACurrentMediaTime()
        case .ended, .cancelled:
            pinchStartDistance = nil
            lastInteractionTime = CACurrentMediaTime()
        default:
            break
        }
    }

    func handleKeyboardZoom(direction: Int) {
        guard !isAnimatingFlyTo else { return }
        let factor = direction > 0 ? 1 / keyboardZoomFactor : keyboardZoomFactor
        renderer.adjustZoom(by: factor)
        lastInteractionTime = CACurrentMediaTime()
    }

    func handleTap(at point: CGPoint) {
        guard let sceneView, !isAnimatingFlyTo else { return }
        if renderer.handleTap(at: point, in: sceneView) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            lastInteractionTime = CACurrentMediaTime()
        }
    }

    func flyTo(city: City, completion: (() -> Void)? = nil) {
        isAnimatingFlyTo = true
        isDragging = false
        momentum = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        renderer.flyTo(city: city) { [weak self] in
            self?.isAnimatingFlyTo = false
            completion?()
        }
    }

    private func startTickTimer() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard !isAnimatingFlyTo, !isDragging else { return }

        let now = CACurrentMediaTime()
        let isIdle = (now - lastInteractionTime) > idleDelay
        let momentumAngle = 2 * acos(min(1, abs(momentum.real)))

        if momentumAngle > 0.00005 {
            renderer.applyMomentum(momentum)
            let dampedAngle = momentumAngle * friction
            if dampedAngle > 0.00005 {
                let axisLength = simd_length(momentum.imag)
                if axisLength > 0.00001 {
                    let axis = momentum.imag / axisLength
                    momentum = simd_quatf(angle: dampedAngle, axis: axis)
                } else {
                    momentum = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                }
            } else {
                momentum = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            }
            lastInteractionTime = now
        } else if isIdle {
            renderer.applyIdleRotation(speed: autoRotateSpeed)
        }
    }
}
