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
        cityMarkers = cities.enumerated().map { index, city in
            let marker = EarthCityMarker(city: city, paletteIndex: index)
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
        geometry.segmentCount = 96

        let material = SCNMaterial()
        material.diffuse.contents = loadImage(named: "earth_day")
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.diffuse.mipFilter = .linear
        // Day texture is intentionally muted; lift diffuse so land/ocean stay readable.
        material.diffuse.intensity = 1.55
        // Population-density emission: neon purple — strongest on the night side.
        material.emission.contents = loadImage(named: "earth_night")
        material.emission.intensity = 1.45
        material.lightingModel = .blinn
        material.shininess = 0.04
        material.specular.contents = UIColor(white: 0.06, alpha: 1)
        // Soften self-shadowing so the night hemisphere still shows continents/oceans.
        material.ambient.contents = UIColor(white: 0.55, alpha: 1)

        geometry.materials = [material]
        earthNode.geometry = geometry
    }

    /// Soft purple 2D silhouette halo — a camera-facing ring just outside the globe limb.
    /// Does not light the Earth surface; only separates the disc from the background.
    private func buildAtmosphere() {
        // 20% shorter than prior 2.70 falloff extent
        let glowSize: CGFloat = 2.56
        let plane = SCNPlane(width: glowSize, height: glowSize)
        let material = SCNMaterial()
        let tex = Self.limbGlowTexture
        material.diffuse.contents = tex
        material.emission.contents = tex
        material.emission.intensity = 0.01125
        material.lightingModel = .constant
        material.isDoubleSided = true
        // Alpha blend so the soft tail dissolves into the background instead of stacking additively.
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        plane.materials = [material]

        let glow = SCNNode(geometry: plane)
        glow.constraints = [SCNBillboardConstraint()]
        glow.renderingOrder = -1
        glow.castsShadow = false
        earthNode.addChildNode(glow)
    }

    private static let limbGlowTexture = makeLimbGlowTexture()

    /// Annular purple soft-glow: transparent center, soft long falloff that fades into the background.
    private static func makeLimbGlowTexture() -> UIImage {
        let dim: CGFloat = 512
        let size = CGSize(width: dim, height: dim)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: dim * 0.5, y: dim * 0.5)
            // glowSize 2.56 → limb (radius 1.0) at 1.0/1.28 ≈ 0.781 of half-extent
            let half = dim * 0.5
            let colors = [
                UIColor(red: 0.72, green: 0.28, blue: 1.0, alpha: 0).cgColor,
                UIColor(red: 0.78, green: 0.32, blue: 1.0, alpha: 0).cgColor,
                UIColor(red: 0.80, green: 0.38, blue: 1.0, alpha: 0.00875).cgColor,
                UIColor(red: 0.62, green: 0.26, blue: 0.98, alpha: 0.0045).cgColor,
                UIColor(red: 0.45, green: 0.16, blue: 0.85, alpha: 0.00175).cgColor,
                UIColor(red: 0.30, green: 0.10, blue: 0.55, alpha: 0.0005).cgColor,
                UIColor(red: 0.20, green: 0.06, blue: 0.35, alpha: 0).cgColor,
            ] as CFArray
            // Peak near limb, then a smooth ease-out into the background
            let locations: [CGFloat] = [0, 0.76, 0.79, 0.86, 0.92, 0.97, 1.0]
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)
            else { return }
            cg.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: half,
                options: [.drawsAfterEndLocation]
            )
        }
    }

    private func buildLights() {
        // SceneKit's "1.0" lighting scale is ~1000 intensity — keep fill strong enough
        // that land/ocean remain visible on the night side, not just purple dots.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 620
        ambient.light?.color = UIColor(red: 0.78, green: 0.80, blue: 0.88, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        sunLightNode.light = SCNLight()
        sunLightNode.light?.type = .directional
        sunLightNode.light?.intensity = 1650
        sunLightNode.light?.color = UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1)
        sunLightNode.light?.castsShadow = false
        updateSunLightPosition()
        scene.rootNode.addChildNode(sunLightNode)

        // Gentle fill from the camera side so the facing hemisphere never goes black.
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 380
        fill.light?.color = UIColor(red: 0.70, green: 0.74, blue: 0.90, alpha: 1)
        fill.light?.castsShadow = false
        fill.position = SCNVector3(0, 0.4, 6)
        fill.look(at: SCNVector3Zero)
        cameraNode.addChildNode(fill)
    }

    private func buildCamera() {
        let camera = SCNCamera()
        camera.zNear = 0.05
        camera.zFar = 100
        camera.fieldOfView = 40
        camera.wantsDepthOfField = false
        // Mild bloom so neon population hubs glow without washing the diffuse topo.
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0.35
        camera.bloomIntensity = 0.28
        camera.bloomThreshold = 0.55
        camera.bloomBlurRadius = 4.0
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
            if dist < 72, best == nil || dist < best!.1 { best = (marker, dist) }
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

    /// Classic red map-pin texture (shared across markers).
    private static let pinTexture = makeMapPinTexture()

    /// Pin size in globe units; tip sits on the surface, head rises toward the camera.
    /// 100% larger than the initial red-pin sizing (0.034 × 0.048).
    private static let pinWidth: CGFloat = 0.068
    private static let pinHeight: CGFloat = 0.096

    init(city: City, paletteIndex: Int) {
        self.city = city
        _ = paletteIndex
        // Tip of the pin is anchored just above the sphere surface at the true lat/lon.
        let position = EarthGeo.position(
            latitude: city.latitude,
            longitude: city.longitude,
            radius: 1.006
        )

        let root = SCNNode()
        root.position = position
        root.renderingOrder = 20

        let billboard = SCNNode()
        billboard.constraints = [SCNBillboardConstraint()]
        root.addChildNode(billboard)

        let pin = SCNPlane(width: Self.pinWidth, height: Self.pinHeight)
        let pinMat = SCNMaterial()
        pinMat.diffuse.contents = Self.pinTexture
        pinMat.emission.contents = Self.pinTexture
        pinMat.emission.intensity = 0.35
        pinMat.lightingModel = .constant
        pinMat.blendMode = .alpha
        pinMat.isDoubleSided = true
        pinMat.writesToDepthBuffer = false
        pinMat.readsFromDepthBuffer = true
        pinMat.transparencyMode = .aOne
        pin.materials = [pinMat]

        let pinNode = SCNNode(geometry: pin)
        // Offset so the droplet tip (bottom of the texture) sits at the geo position.
        pinNode.position = SCNVector3(0, Float(Self.pinHeight) * 0.5, 0)
        billboard.addChildNode(pinNode)

        // Invisible larger hit target for easier taps.
        let hitPlane = SCNPlane(width: Self.pinWidth * 1.8, height: Self.pinHeight * 1.4)
        let hitMat = SCNMaterial()
        hitMat.diffuse.contents = UIColor(white: 1, alpha: 0.01)
        hitMat.lightingModel = .constant
        hitMat.blendMode = .alpha
        hitMat.writesToDepthBuffer = false
        hitMat.readsFromDepthBuffer = false
        hitPlane.materials = [hitMat]
        let hitNode = SCNNode(geometry: hitPlane)
        hitNode.position = SCNVector3(0, Float(Self.pinHeight) * 0.45, 0.001)
        billboard.addChildNode(hitNode)

        self.node = root
    }

    func contains(_ hitNode: SCNNode) -> Bool {
        hitNode === node || node.childNodes.contains { child in
            hitNode === child || child.childNodes.contains(hitNode)
        }
    }

    // MARK: - Textures (shared, generated once)

    /// Traditional red upside-down droplet / map pin with a white center disc.
    private static func makeMapPinTexture() -> UIImage {
        let size = CGSize(width: 128, height: 180)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let red = UIColor(red: 0.90, green: 0.18, blue: 0.18, alpha: 1)

            let cx = size.width * 0.5
            let headRadius = size.width * 0.34
            let headCenter = CGPoint(x: cx, y: size.height * 0.34)
            let tip = CGPoint(x: cx, y: size.height * 0.96)
            let flankY = headCenter.y + headRadius * 0.2
            let flankHalf = headRadius * 0.82

            let pin = UIBezierPath()
            // Pointed tip + flanks that tuck under the circular head.
            pin.move(to: tip)
            pin.addLine(to: CGPoint(x: cx - flankHalf, y: flankY))
            pin.addLine(to: CGPoint(x: cx + flankHalf, y: flankY))
            pin.close()
            // Circular head.
            pin.append(
                UIBezierPath(
                    ovalIn: CGRect(
                        x: headCenter.x - headRadius,
                        y: headCenter.y - headRadius,
                        width: headRadius * 2,
                        height: headRadius * 2
                    )
                )
            )

            cg.saveGState()
            cg.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 5,
                color: UIColor.black.withAlphaComponent(0.4).cgColor
            )
            red.setFill()
            pin.fill()
            cg.restoreGState()

            let discRadius = headRadius * 0.36
            let disc = UIBezierPath(
                ovalIn: CGRect(
                    x: headCenter.x - discRadius,
                    y: headCenter.y - discRadius,
                    width: discRadius * 2,
                    height: discRadius * 2
                )
            )
            UIColor.white.setFill()
            disc.fill()
        }
    }
}
