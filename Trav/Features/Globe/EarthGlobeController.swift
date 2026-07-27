import SceneKit
import simd
import UIKit

/// Manages gesture input, momentum, and idle auto-rotation for the globe.
@MainActor
final class EarthGlobeController: NSObject, SCNSceneRendererDelegate {
    let renderer: EarthGlobeRenderer

    private weak var sceneView: SCNView?

    private var lastInteractionTime: CFTimeInterval = 0
    private var isDragging = false
    private var dragAnchorWorld = SIMD3<Float>(0, 0, 1)
    private var lastDragWorld = SIMD3<Float>(0, 0, 1)
    private var momentum = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private var pinchStartDistance: Float?
    private var isTabActive = true

    private let autoRotateSpeed: Float = 0.004
    private let idleDelay: CFTimeInterval = 2.5
    private let friction: Float = 0.94
    private let keyboardZoomFactor: Float = 1.12

    var isAnimatingFlyTo = false

    init(renderer: EarthGlobeRenderer) {
        self.renderer = renderer
        super.init()
    }

    func attach(to view: SCNView) {
        sceneView = view
        view.delegate = self
        syncRenderingMode()
    }

    /// Pause SceneKit when Explore is hidden so other tabs are not fighting a 60fps globe.
    func setRenderingActive(_ active: Bool) {
        isTabActive = active
        syncRenderingMode()
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
            syncRenderingMode()

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
            syncRenderingMode()

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
            syncRenderingMode()
        case .changed:
            guard let start = pinchStartDistance else { return }
            renderer.setCameraDistance(start / Float(scale))
            lastInteractionTime = CACurrentMediaTime()
        case .ended, .cancelled:
            pinchStartDistance = nil
            lastInteractionTime = CACurrentMediaTime()
            syncRenderingMode()
        default:
            break
        }
    }

    func handleKeyboardZoom(direction: Int) {
        guard !isAnimatingFlyTo else { return }
        let factor = direction > 0 ? 1 / keyboardZoomFactor : keyboardZoomFactor
        renderer.adjustZoom(by: factor)
        lastInteractionTime = CACurrentMediaTime()
        syncRenderingMode()
    }

    func handleTap(at point: CGPoint) {
        guard let sceneView, !isAnimatingFlyTo else { return }
        if renderer.handleTap(at: point, in: sceneView) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            lastInteractionTime = CACurrentMediaTime()
            syncRenderingMode()
        }
    }

    func flyTo(city: City, completion: (() -> Void)? = nil) {
        isAnimatingFlyTo = true
        isDragging = false
        momentum = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        syncRenderingMode()
        renderer.flyTo(city: city) { [weak self] in
            self?.isAnimatingFlyTo = false
            self?.lastInteractionTime = CACurrentMediaTime()
            self?.syncRenderingMode()
            completion?()
        }
    }

    /// Restores the default wide framing after returning from a city.
    func resetZoom(animated: Bool = true) {
        isAnimatingFlyTo = false
        isDragging = false
        pinchStartDistance = nil
        momentum = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        renderer.resetZoom(animated: animated)
        lastInteractionTime = CACurrentMediaTime()
        syncRenderingMode()
    }

    // MARK: - SCNSceneRendererDelegate

    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // SCNView invokes this on the main thread; fall back if not.
        guard Thread.isMainThread else {
            Task { @MainActor [weak self] in
                self?.tick()
                self?.renderer.updateCityMarkerVisibility()
                self?.syncRenderingMode()
            }
            return
        }
        MainActor.assumeIsolated {
            tick()
            self.renderer.updateCityMarkerVisibility()
            syncRenderingMode()
        }
    }

    private var hasActiveMomentum: Bool {
        let momentumAngle = 2 * acos(min(1, abs(momentum.real)))
        return momentumAngle > 0.00005
    }

    private func syncRenderingMode() {
        guard let view = sceneView else { return }

        guard isTabActive else {
            view.rendersContinuously = false
            view.isPlaying = false
            return
        }

        let interactive = isDragging || pinchStartDistance != nil || isAnimatingFlyTo || hasActiveMomentum
        view.isPlaying = true
        // Continuous rendering only while the user (or momentum) is moving the globe.
        // Idle auto-spin steps one frame at a time so we don't burn GPU at 30fps forever.
        view.rendersContinuously = interactive
        view.preferredFramesPerSecond = interactive ? 60 : 15
    }

    private func tick() {
        guard isTabActive, !isAnimatingFlyTo, !isDragging else { return }

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
            syncRenderingMode()
        } else if isIdle {
            renderer.applyIdleRotation(speed: autoRotateSpeed)
            // Single-frame render for idle spin — no continuous GPU loop.
            sceneView?.rendersContinuously = false
            sceneView?.isPlaying = true
        } else {
            syncRenderingMode()
        }
    }
}
