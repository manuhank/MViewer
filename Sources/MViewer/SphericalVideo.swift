import AVFoundation
import CoreMedia
import SceneKit
import SpriteKit

/// Detects 360° (equirectangular) videos via CoreMedia's projection metadata
/// or, failing that, by scanning the container for Spherical Video V1/V2
/// signaling (GSpherical XML, sv3d/proj boxes).
enum SphericalDetector {
    static func isSpherical(url: URL, asset: AVURLAsset) async -> Bool {
        if #available(macOS 15.0, *),
           let track = try? await asset.loadTracks(withMediaType: .video).first,
           let descriptions = try? await track.load(.formatDescriptions) {
            for description in descriptions {
                if let kind = CMFormatDescriptionGetExtension(
                    description,
                    extensionKey: kCMFormatDescriptionExtension_ProjectionKind) as? String,
                    kind == kCMFormatDescriptionProjectionKind_Equirectangular as String {
                    return true
                }
            }
        }
        return scanForSphericalSignaling(url: url)
    }

    /// The spherical metadata lives in the moov box, which sits at the start
    /// (streamable files) or the end of the container — scan both.
    private static func scanForSphericalSignaling(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let chunkSize = 8 * 1024 * 1024

        func isSpherical(_ data: Data) -> Bool {
            if data.range(of: Data("GSpherical".utf8)) != nil { return true }
            if data.range(of: Data("equirectangular".utf8)) != nil { return true }
            return data.range(of: Data("sv3d".utf8)) != nil
                && data.range(of: Data("proj".utf8)) != nil
        }

        if let head = try? handle.read(upToCount: chunkSize), isSpherical(head) {
            return true
        }
        if let size = try? handle.seekToEnd(), size > UInt64(chunkSize) {
            try? handle.seek(toOffset: size - UInt64(chunkSize))
            if let tail = try? handle.read(upToCount: chunkSize), isSpherical(tail) {
                return true
            }
        }
        return false
    }
}

/// Renders an equirectangular video on the inside of a sphere: drag to look
/// around, scroll to zoom (field of view).
final class SphericalVideoView: SCNView {
    private let cameraNode = SCNNode()
    private var yaw: CGFloat = 0
    private var pitch: CGFloat = 0

    func configure(player: AVPlayer, videoSize: CGSize) {
        let scene = SCNScene()

        let size = CGSize(width: max(videoSize.width, 2), height: max(videoSize.height, 2))
        let videoScene = SKScene(size: size)
        let videoNode = SKVideoNode(avPlayer: player)
        videoNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        videoNode.size = size
        videoNode.yScale = -1
        videoScene.addChild(videoNode)

        let sphere = SCNSphere(radius: 30)
        sphere.segmentCount = 96
        let material = SCNMaterial()
        material.diffuse.contents = videoScene
        material.isDoubleSided = true
        material.lightingModel = .constant
        sphere.firstMaterial = material

        let sphereNode = SCNNode(geometry: sphere)
        // Mirror so the projection reads correctly from inside the sphere.
        sphereNode.scale = SCNVector3(-1, 1, 1)
        scene.rootNode.addChildNode(sphereNode)

        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 80
        cameraNode.camera?.zNear = 0.1
        scene.rootNode.addChildNode(cameraNode)

        self.scene = scene
        pointOfView = cameraNode
        backgroundColor = .black
        rendersContinuously = true
        isPlaying = true
        yaw = 0
        pitch = 0
        updateCamera()
    }

    func teardown() {
        isPlaying = false
        scene = nil
    }

    override func mouseDragged(with event: NSEvent) {
        yaw += event.deltaX * 0.004
        pitch += event.deltaY * 0.004
        pitch = min(max(pitch, -.pi / 2), .pi / 2)
        updateCamera()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let camera = cameraNode.camera else { return }
        camera.fieldOfView = min(max(camera.fieldOfView - event.scrollingDeltaY * 0.25, 30), 110)
    }

    private func updateCamera() {
        cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0)
    }
}
