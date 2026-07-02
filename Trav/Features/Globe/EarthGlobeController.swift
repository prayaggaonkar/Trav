import SceneKit
import UIKit

/// Manages gesture input, momentum, and idle auto-rotation for the globe.
@MainActor
final class EarthGlobeController: NSObject {
    let renderer: EarthGlobeRenderer

    private weak var sceneView: SCNView?
    private nonisolated(unsafe) var tickTimer: Timer?

    private var velocityX: Float = 0
    private var velocityY: Float = 0
    private var lastInteractionTime: CFTimeInterval = 0

    private let autoRotateSpeed: Float = 0.004
    private let idleDelay: CFTimeInterval = 2.5
    private let friction: Float = 0.94

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

    func handlePan(translation: CGPoint, state: UIGestureRecognizer.State) {
        guard !isAnimatingFlyTo else { return }

        let sensitivity: Float = 0.004
        let deltaX = Float(translation.x) * sensitivity
        let deltaY = Float(translation.y) * sensitivity

        renderer.rotateEarth(deltaX: deltaX, deltaY: -deltaY)
        velocityX = deltaX
        velocityY = -deltaY
        lastInteractionTime = CACurrentMediaTime()
    }

    func handlePinch(scale: CGFloat, state: UIGestureRecognizer.State) {
        guard !isAnimatingFlyTo, state == .changed else { return }
        let newDistance = renderer.cameraDistance / Float(scale)
        renderer.cameraDistance = max(
            renderer.minCameraDistance,
            min(renderer.maxCameraDistance, newDistance)
        )
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
        velocityX = 0
        velocityY = 0
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
        guard !isAnimatingFlyTo else { return }

        let now = CACurrentMediaTime()
        let isIdle = (now - lastInteractionTime) > idleDelay

        if abs(velocityX) > 0.0001 || abs(velocityY) > 0.0001 {
            renderer.rotateEarth(deltaX: velocityX, deltaY: velocityY)
            velocityX *= friction
            velocityY *= friction
            if abs(velocityX) < 0.0001 { velocityX = 0 }
            if abs(velocityY) < 0.0001 { velocityY = 0 }
        } else if isIdle {
            renderer.applyIdleRotation(speed: autoRotateSpeed)
        }
    }
}
