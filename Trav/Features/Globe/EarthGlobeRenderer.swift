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

    var onCitySelected: ((City) -> Void)?

    var cameraDistance: Float = 2.75 {
        didSet { updateCameraPosition() }
    }

    let minCameraDistance: Float = 2.0
    let maxCameraDistance: Float = 4.5

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

    func rotateEarth(deltaX: Float, deltaY: Float) {
        earthNode.eulerAngles.y += deltaX
        earthNode.eulerAngles.x = clamp(
            earthNode.eulerAngles.x + deltaY,
            min: -Float.pi / 2.5,
            max: Float.pi / 2.5
        )
    }

    func applyIdleRotation(speed: Float) {
        earthNode.eulerAngles.y += speed
    }

    func flyTo(city: City, completion: (() -> Void)? = nil) {
        let lat = Float(city.latitude * .pi / 180)
        let lon = Float(city.longitude * .pi / 180)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.1
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        SCNTransaction.completionBlock = completion

        earthNode.eulerAngles = SCNVector3(lat * 0.75, -lon, 0)
        cameraDistance = 2.2
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
        buildAtmosphere()
        buildLights()
        buildCamera()

        earthNode.eulerAngles = SCNVector3(-0.15, -1.2, 0)

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
        camera.fieldOfView = 38
        camera.wantsDepthOfField = true
        camera.focusDistance = 2.5
        camera.fStop = 20
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

    private func clamp(_ value: Float, min: Float, max: Float) -> Float {
        Swift.max(min, Swift.min(max, value))
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
