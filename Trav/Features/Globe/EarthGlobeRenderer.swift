import SceneKit
import UIKit
import simd

/// SceneKit scene for the interactive Earth globe.
/// Uses bundled 2K textures and no custom shader modifiers — avoids SceneKit shader failures.
@MainActor
final class EarthGlobeRenderer {
    let scene = SCNScene()

    private(set) var earthNode = SCNNode()
    private(set) var cameraNode = SCNNode()
    private var sunLightNode = SCNNode()

    private var cityMarkers: [EarthCityMarker] = []
    private var sunDirection = EarthSunPosition.direction()
    private var orientation = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))

    var onCitySelected: ((City) -> Void)?

    /// Default / maximum zoom-out distance (full globe in view).
    /// Default / max zoom-out — 8% closer than 5.0 so the globe reads larger at rest.
    static let maxZoomOutDistance: Float = 4.63
    /// Minimum zoom-in for 2K textures without visible upscaling blur.
    static let maxZoomInDistance: Float = 2.2

    var cameraDistance: Float = maxZoomOutDistance {
        didSet { updateCameraPosition() }
    }

    var minCameraDistance: Float { Self.maxZoomInDistance }
    var maxCameraDistance: Float { Self.maxZoomOutDistance }

    func setCameraDistance(_ distance: Float) {
        cameraDistance = max(minCameraDistance, min(maxCameraDistance, distance))
    }

    /// Multiplicative zoom step for keyboard / discrete controls.
    func adjustZoom(by factor: Float) {
        setCameraDistance(cameraDistance * factor)
    }

    init() {
        buildScene()
        startSunTimer()
    }

    func setCities(_ cities: [City]) {
        cityMarkers.forEach { $0.node.removeFromParentNode() }
        cityMarkers = cities.map { city in
            let marker = EarthCityMarker(city: city)
            earthNode.addChildNode(marker.node)
            return marker
        }
    }

    var currentOrientation: simd_quatf { orientation }

    func setOrientation(_ newOrientation: simd_quatf) {
        var q = simd_normalize(newOrientation)
        // Keep quaternion on the same hyper-hemisphere for smooth interpolation.
        if simd_dot(q.vector, orientation.vector) < 0 {
            q = -q
        }
        orientation = q
        applyOrientation()
    }

    /// Applies a small inertial spin after the user lifts their finger.
    func applyMomentum(_ delta: simd_quatf) {
        orientation = simd_normalize(shortestPath(delta) * orientation)
        applyOrientation()
    }

    /// One frame of grab-and-drag rotation; composes smoothly frame-to-frame.
    func applyDragDelta(from previousWorld: SIMD3<Float>, to targetWorld: SIMD3<Float>) {
        let delta = shortestRotation(from: previousWorld, to: targetWorld)
        var next = simd_normalize(delta * orientation)
        if simd_dot(next.vector, orientation.vector) < 0 {
            next = -next
        }
        orientation = next
        applyOrientation()
    }

    func shortestRotationForMomentum(from previousWorld: SIMD3<Float>, to targetWorld: SIMD3<Float>) -> simd_quatf {
        shortestRotation(from: previousWorld, to: targetWorld)
    }

    /// World-space unit direction under a screen point on the virtual trackball.
    func worldDirectionOnSphere(from point: CGPoint, in view: SCNView) -> SIMD3<Float> {
        let cameraDirection = trackballDirectionInCameraSpace(from: point, in: view)
        return transformDirectionToWorld(cameraDirection, in: view)
    }

    func applyIdleRotation(speed: Float) {
        orientation = simd_quatf(angle: speed, axis: SIMD3(0, 1, 0)) * orientation
        applyOrientation()
    }

    func flyTo(city: City, completion: (() -> Void)? = nil) {
        let cityDirection = EarthGeo.unitDirection(
            latitude: city.latitude,
            longitude: city.longitude
        )
        let lat = Float(city.latitude * .pi / 180)
        var targetOrientation = simd_quatf(from: cityDirection, to: SIMD3(0, 0, 1))
        targetOrientation = simd_quatf(angle: lat * 0.25, axis: SIMD3(1, 0, 0)) * targetOrientation

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.1
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = completion

        orientation = targetOrientation
        applyOrientation()
        cameraDistance = 3.2
        SCNTransaction.commit()
    }

    /// Returns the camera to the default wide zoom (full globe in view).
    func resetZoom(animated: Bool = true) {
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.85
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cameraDistance = Self.maxZoomOutDistance
            SCNTransaction.commit()
        } else {
            cameraDistance = Self.maxZoomOutDistance
        }
    }

    func handleTap(at point: CGPoint, in view: SCNView) -> Bool {
        let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
        for hit in hits {
            if let marker = cityMarkers.first(where: { $0.contains(hit.node) }) {
                flyTo(city: marker.city) { [weak self] in self?.onCitySelected?(marker.city) }
                return true
            }
        }
        if let nearest = nearestMarker(to: point, in: view) {
            flyTo(city: nearest.city) { [weak self] in self?.onCitySelected?(nearest.city) }
            return true
        }
        return false
    }

    // MARK: - Scene

    private func buildScene() {
        scene.background.contents = UIColor.clear

        buildEarth()
        buildAtmosphere()
        buildLights()
        buildCamera()

        orientation = orientationFromEuler(x: -0.15, y: -1.2, z: 0)
        applyOrientation()

        scene.rootNode.addChildNode(earthNode)
        scene.rootNode.addChildNode(cameraNode)
    }

    private func buildEarth() {
        let geometry = SCNSphere(radius: 1.0)
        geometry.segmentCount = 128

        let material = SCNMaterial()
        material.diffuse.contents = loadImage(named: "earth_day")
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        // City lights visible on the dark side via emission; sun light handles day side.
        material.emission.contents = loadImage(named: "earth_night")
        material.lightingModel = .blinn
        material.shininess = 0.08

        geometry.materials = [material]
        earthNode.geometry = geometry
    }

    /// Soft atmospheric shell — no custom shaders.
    private func buildAtmosphere() {
        let geometry = SCNSphere(radius: 1.035)
        geometry.segmentCount = 72

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.clear
        material.emission.contents = UIColor(red: 0.35, green: 0.62, blue: 1.0, alpha: 0.15)
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.blendMode = .add
        material.transparency = 0.18

        geometry.materials = [material]
        earthNode.addChildNode(SCNNode(geometry: geometry))
    }

    private func buildLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 120
        ambient.light?.color = UIColor(white: 0.75, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        sunLightNode.light = SCNLight()
        sunLightNode.light?.type = .directional
        sunLightNode.light?.intensity = 1200
        sunLightNode.light?.castsShadow = false
        updateSunLightPosition()
        scene.rootNode.addChildNode(sunLightNode)
    }

    private func buildCamera() {
        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 100
        camera.fieldOfView = 40
        // Keep the full globe sharp at all zoom levels (fixed DOF was blurring close views).
        camera.wantsDepthOfField = false
        cameraNode.camera = camera
        updateCameraPosition()
    }

    private func updateCameraPosition() {
        cameraNode.position = SCNVector3(0, 0, cameraDistance)
        cameraNode.look(at: SCNVector3Zero)
    }

    private func updateSunLightPosition() {
        sunDirection = EarthSunPosition.direction()
        sunLightNode.position = SCNVector3(sunDirection.x * 8, sunDirection.y * 8, sunDirection.z * 8)
        sunLightNode.look(at: SCNVector3Zero)
    }

    private func startSunTimer() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateSunLightPosition() }
        }
    }

    private func applyOrientation() {
        earthNode.simdOrientation = orientation
    }

    /// Shoemake arcball in camera space — single continuous projection (no ray/hybrid switching).
    private func trackballDirectionInCameraSpace(from point: CGPoint, in view: SCNView) -> SIMD3<Float> {
        let width = max(Float(view.bounds.width), 1)
        let height = max(Float(view.bounds.height), 1)
        let x = 2 * Float(point.x) / width - 1
        let y = 1 - 2 * Float(point.y) / height

        let lengthSquared = x * x + y * y
        if lengthSquared <= 1 {
            let z = sqrt(max(0, 1 - lengthSquared))
            return simd_normalize(SIMD3(x, y, z))
        }

        // Rim: project onto equator of the virtual ball (smooth continuation past the disk edge).
        let length = sqrt(lengthSquared)
        return simd_normalize(SIMD3(x / length, y / length, 0))
    }

    private func transformDirectionToWorld(_ direction: SIMD3<Float>, in view: SCNView) -> SIMD3<Float> {
        guard let pointOfView = view.pointOfView else { return direction }
        let rotation = simd_quatf(pointOfView.simdWorldTransform)
        return simd_normalize(simd_act(rotation, direction))
    }

    /// Shortest-path rotation between two directions; handles near-opposite vectors stably.
    private func shortestRotation(from a: SIMD3<Float>, to b: SIMD3<Float>) -> simd_quatf {
        let from = simd_normalize(a)
        let to = simd_normalize(b)
        let cosine = simd_dot(from, to)

        if cosine >= 0.999999 {
            return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
        if cosine <= -0.999999 {
            var axis = simd_cross(from, SIMD3(0, 0, 1))
            if simd_length_squared(axis) < 1e-8 {
                axis = simd_cross(from, SIMD3(0, 1, 0))
            }
            return simd_quatf(angle: .pi, axis: simd_normalize(axis))
        }

        return simd_normalize(simd_quatf(from: from, to: to))
    }

    private func shortestPath(_ q: simd_quatf) -> simd_quatf {
        simd_dot(q.vector, orientation.vector) < 0 ? -q : q
    }

    /// SceneKit applies euler angles in X → Y → Z order on the node pivot.
    private func orientationFromEuler(x: Float, y: Float, z: Float) -> simd_quatf {
        let qx = simd_quatf(angle: x, axis: SIMD3(1, 0, 0))
        let qy = simd_quatf(angle: y, axis: SIMD3(0, 1, 0))
        let qz = simd_quatf(angle: z, axis: SIMD3(0, 0, 1))
        return qz * qy * qx
    }

    private func loadImage(named name: String) -> UIImage {
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        if let image = UIImage(named: name) {
            return image
        }
        fatalError("Missing texture: \(name)")
    }

    private func nearestMarker(to point: CGPoint, in view: SCNView) -> EarthCityMarker? {
        var best: (EarthCityMarker, CGFloat)?
        for marker in cityMarkers {
            let projected = view.projectPoint(marker.node.presentation.worldPosition)
            guard projected.z > 0 else { continue }
            let screen = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
            let dist = hypot(screen.x - point.x, screen.y - point.y)
            if dist < 48, best == nil || dist < best!.1 { best = (marker, dist) }
        }
        return best?.0
    }
}

/// Geographic → SceneKit sphere point for equirectangular Earth textures on `SCNSphere`.
/// Verified against SCNSphere texcoords: lon 0° → +Z (texture center), lon +90° → +X.
private enum EarthGeo {
    static func unitDirection(latitude: Double, longitude: Double) -> SIMD3<Float> {
        let lat = Float(latitude * .pi / 180)
        let lon = Float(longitude * .pi / 180)
        return simd_normalize(SIMD3(
            cos(lat) * sin(lon),
            sin(lat),
            cos(lat) * cos(lon)
        ))
    }

    static func position(latitude: Double, longitude: Double, radius: Float) -> SCNVector3 {
        let d = unitDirection(latitude: latitude, longitude: longitude)
        return SCNVector3(d.x * radius, d.y * radius, d.z * radius)
    }
}

private struct EarthCityMarker {
    let city: City
    let node: SCNNode

    /// Shared timeline so every city breathes and ripples together.
    private static let timelineOrigin = CACurrentMediaTime()
    private static let breathPeriod: CFTimeInterval = 2.6
    private static let ripplePeriod: CFTimeInterval = 3.8

    private static let softGlowTexture = makeSoftGlowTexture()
    private static let coreTexture = makeCoreTexture()
    private static let ringTexture = makeRingTexture()

    init(city: City) {
        self.city = city
        let position = EarthGeo.position(
            latitude: city.latitude,
            longitude: city.longitude,
            radius: 1.028
        )

        let root = SCNNode()
        root.position = position
        root.renderingOrder = 10

        // Billboard group: soft day-readable glow + night sparkle + radar ripple.
        let billboard = SCNNode()
        billboard.constraints = [SCNBillboardConstraint()]
        root.addChildNode(billboard)

        // Soft halo — alpha blend so it stays visible on bright day land.
        let haloSize: CGFloat = 0.028
        let halo = SCNPlane(width: haloSize, height: haloSize)
        let haloMat = SCNMaterial()
        haloMat.diffuse.contents = Self.softGlowTexture
        haloMat.emission.contents = Self.softGlowTexture
        haloMat.emission.intensity = 0.55
        haloMat.lightingModel = .constant
        haloMat.blendMode = .alpha
        haloMat.isDoubleSided = true
        haloMat.writesToDepthBuffer = false
        haloMat.readsFromDepthBuffer = true
        halo.materials = [haloMat]
        let haloNode = SCNNode(geometry: halo)
        haloNode.opacity = 0.92
        billboard.addChildNode(haloNode)

        // Hot core — additive so it still reads on the night side.
        let coreSize: CGFloat = 0.014
        let core = SCNPlane(width: coreSize, height: coreSize)
        let coreMat = SCNMaterial()
        coreMat.diffuse.contents = Self.coreTexture
        coreMat.emission.contents = Self.coreTexture
        coreMat.emission.intensity = 1.25
        coreMat.lightingModel = .constant
        coreMat.blendMode = .add
        coreMat.isDoubleSided = true
        coreMat.writesToDepthBuffer = false
        coreMat.readsFromDepthBuffer = true
        core.materials = [coreMat]
        let coreNode = SCNNode(geometry: core)
        billboard.addChildNode(coreNode)

        // Subtle shared breath (opacity + tiny scale) — premium, not distractingly large.
        let breathOpacity = CABasicAnimation(keyPath: "opacity")
        breathOpacity.fromValue = 0.82
        breathOpacity.toValue = 1.0
        breathOpacity.duration = Self.breathPeriod / 2
        breathOpacity.autoreverses = true
        breathOpacity.repeatCount = .infinity
        breathOpacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breathOpacity.beginTime = Self.timelineOrigin

        let breathScale = CABasicAnimation(keyPath: "scale")
        breathScale.fromValue = NSValue(scnVector3: SCNVector3(0.96, 0.96, 0.96))
        breathScale.toValue = NSValue(scnVector3: SCNVector3(1.05, 1.05, 1.05))
        breathScale.duration = Self.breathPeriod / 2
        breathScale.autoreverses = true
        breathScale.repeatCount = .infinity
        breathScale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breathScale.beginTime = Self.timelineOrigin

        billboard.addAnimation(breathOpacity, forKey: "breathOpacity")
        billboard.addAnimation(breathScale, forKey: "breathScale")

        // Small radar ripple — expands and fades every few seconds, synced across cities.
        let ringSize: CGFloat = 0.024
        let ring = SCNPlane(width: ringSize, height: ringSize)
        let ringMat = SCNMaterial()
        ringMat.diffuse.contents = Self.ringTexture
        ringMat.emission.contents = Self.ringTexture
        ringMat.emission.intensity = 0.9
        ringMat.lightingModel = .constant
        ringMat.blendMode = .add
        ringMat.isDoubleSided = true
        ringMat.writesToDepthBuffer = false
        ringMat.readsFromDepthBuffer = true
        ring.materials = [ringMat]
        let ringNode = SCNNode(geometry: ring)
        ringNode.opacity = 0
        billboard.addChildNode(ringNode)

        let rippleScale = CAKeyframeAnimation(keyPath: "scale")
        rippleScale.values = [
            NSValue(scnVector3: SCNVector3(0.7, 0.7, 0.7)),
            NSValue(scnVector3: SCNVector3(1.85, 1.85, 1.85)),
            NSValue(scnVector3: SCNVector3(1.85, 1.85, 1.85))
        ]
        rippleScale.keyTimes = [0, 0.58, 1] as [NSNumber]
        rippleScale.duration = Self.ripplePeriod
        rippleScale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .linear)
        ]

        let rippleOpacity = CAKeyframeAnimation(keyPath: "opacity")
        rippleOpacity.values = [0.42, 0.28, 0, 0] as [NSNumber]
        rippleOpacity.keyTimes = [0, 0.22, 0.62, 1] as [NSNumber]
        rippleOpacity.duration = Self.ripplePeriod
        rippleOpacity.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .linear)
        ]

        let ripple = CAAnimationGroup()
        ripple.animations = [rippleScale, rippleOpacity]
        ripple.duration = Self.ripplePeriod
        ripple.repeatCount = .infinity
        ripple.beginTime = Self.timelineOrigin
        ripple.isRemovedOnCompletion = false
        ringNode.addAnimation(ripple, forKey: "ripple")

        self.node = root
    }

    func contains(_ hitNode: SCNNode) -> Bool {
        hitNode === node || node.childNodes.contains { child in
            hitNode === child || child.childNodes.contains(hitNode)
        }
    }

    // MARK: - Textures (shared, generated once)

    /// Soft cool-white bloom — readable on day land via alpha coverage.
    private static func makeSoftGlowTexture() -> UIImage {
        makeRadialTexture(size: 256) { r2 in
            let bloom = exp(-r2 * 4.8)
            let core = exp(-r2 * 22.0)
            let alpha = min(1.0, bloom * 0.48 + core * 0.4)
            return (0.86, 0.93, 1.0, alpha)
        }
    }

    /// Tight additive spark for night-side visibility.
    private static func makeCoreTexture() -> UIImage {
        makeRadialTexture(size: 128) { r2 in
            let core = exp(-r2 * 28.0)
            let rim = exp(-r2 * 10.0) * 0.35
            let alpha = min(1.0, core + rim)
            return (0.92, 0.97, 1.0, alpha)
        }
    }

    /// Thin circular ring for the radar ripple.
    private static func makeRingTexture() -> UIImage {
        let size = 256
        let center = Double(size - 1) / 2
        let outer: Double = 0.46
        let inner: Double = 0.36
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Double(x) - center) / center
                let dy = (Double(y) - center) / center
                let r = (dx * dx + dy * dy).squareRoot()
                let mid = (outer + inner) * 0.5
                let half = (outer - inner) * 0.5
                let ring = max(0.0, 1.0 - abs(r - mid) / half)
                let alpha = min(1.0, ring * ring * 0.85)
                let idx = (y * size + x) * 4
                pixels[idx] = UInt8(min(255, 255 * alpha * 0.88))
                pixels[idx + 1] = UInt8(min(255, 255 * alpha * 0.95))
                pixels[idx + 2] = UInt8(min(255, 255 * alpha * 1.0))
                pixels[idx + 3] = UInt8(min(255, 255 * alpha))
            }
        }
        return image(from: pixels, size: size)
    }

    private static func makeRadialTexture(
        size: Int,
        sample: (_ r2: Double) -> (Double, Double, Double, Double)
    ) -> UIImage {
        let center = Double(size - 1) / 2
        let cornerRadius = center * (2.0).squareRoot()
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Double(x) - center) / cornerRadius
                let dy = (Double(y) - center) / cornerRadius
                let (r, g, b, a) = sample(dx * dx + dy * dy)
                let idx = (y * size + x) * 4
                pixels[idx] = UInt8(min(255, 255 * r * a))
                pixels[idx + 1] = UInt8(min(255, 255 * g * a))
                pixels[idx + 2] = UInt8(min(255, 255 * b * a))
                pixels[idx + 3] = UInt8(min(255, 255 * a))
            }
        }
        return image(from: pixels, size: size)
    }

    private static func image(from pixels: [UInt8], size: Int) -> UIImage {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                  width: size,
                  height: size,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: size * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage)
    }
}
