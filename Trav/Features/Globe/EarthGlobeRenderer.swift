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
    static let maxZoomOutDistance: Float = 5.0
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
        let lat = Float(city.latitude * .pi / 180)
        let lon = Float(city.longitude * .pi / 180)
        let cityDirection = simd_normalize(SIMD3(
            cos(lat) * cos(lon),
            sin(lat),
            cos(lat) * sin(lon)
        ))
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
        scene.background.contents = loadImage(named: "stars")

        buildEarth()
        buildNorthCloudVeil()
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

    /// Faint cloud veil over the geographic north cap to soften the equirectangular pole artifact.
    private func buildNorthCloudVeil() {
        let geometry = SCNSphere(radius: 1.017)
        geometry.segmentCount = 128

        let material = SCNMaterial()
        material.diffuse.contents = loadImage(named: "clouds")
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .clamp
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.lightingModel = .constant
        material.isDoubleSided = false
        material.cullMode = .back
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.shaderModifiers = [.fragment: Self.northCloudVeilShader]

        geometry.materials = [material]
        earthNode.addChildNode(SCNNode(geometry: geometry))
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

    /// Geographic mask + luminance from clouds.jpg; only affects the northern cap.
    private static let northCloudVeilShader = """
    #pragma body
    float north = clamp(_geometry.normal.y, 0.0, 1.0);
    float region = smoothstep(0.86, 0.985, north);
    float density = dot(_output.color.rgb, float3(0.333));
    density = smoothstep(0.12, 0.72, density);
    float alpha = density * region * 0.44;
    _output.color = float4(0.96, 0.98, 1.0, alpha);
    """

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

private struct EarthCityMarker {
    let city: City
    let node: SCNNode

    init(city: City) {
        self.city = city
        let lat = Float(city.latitude * .pi / 180)
        let lon = Float(city.longitude * .pi / 180)
        let r: Float = 1.014
        let position = SCNVector3(r * cos(lat) * cos(lon), r * sin(lat), r * cos(lat) * sin(lon))

        let root = SCNNode()
        root.position = position
        root.look(at: SCNVector3(position.x * 2, position.y * 2, position.z * 2))

        let core = SCNSphere(radius: 0.011)
        let coreMat = SCNMaterial()
        coreMat.lightingModel = .constant
        coreMat.emission.contents = UIColor(red: 1, green: 0.42, blue: 0.24, alpha: 1)
        core.materials = [coreMat]
        root.addChildNode(SCNNode(geometry: core))

        let halo = SCNSphere(radius: 0.022)
        let haloMat = SCNMaterial()
        haloMat.lightingModel = .constant
        haloMat.emission.contents = UIColor(red: 1, green: 0.36, blue: 0.21, alpha: 0.35)
        haloMat.transparency = 0.6
        halo.materials = [haloMat]
        let haloNode = SCNNode(geometry: halo)
        root.addChildNode(haloNode)

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.35
        pulse.toValue = 0.9
        pulse.duration = 2.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        haloNode.addAnimation(pulse, forKey: "pulse")

        self.node = root
    }

    func contains(_ hitNode: SCNNode) -> Bool {
        hitNode === node || node.childNodes.contains(hitNode)
    }
}
