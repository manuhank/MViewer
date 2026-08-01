import Foundation
import ImageIO
import QuartzCore

/// Plays multi-frame images (GIF, animated WebP, APNG, HEICS) on a CALayer.
/// Frames are decoded on a background queue one step ahead of display and
/// cached when the whole sequence fits in a reasonable memory budget.
final class FrameAnimator {
    private let source: CGImageSource
    private let frameCount: Int
    private let delays: [Double]
    private weak var targetLayer: CALayer?

    private var cache: [Int: CGImage] = [:]
    private let cacheAll: Bool
    private var index = 0
    private var running = false
    private let decodeQueue = DispatchQueue(label: "mviewer.frame-decode", qos: .userInteractive)

    let canvasSize: CGSize

    init(source: CGImageSource, layer: CALayer) {
        self.source = source
        self.targetLayer = layer
        self.frameCount = CGImageSourceGetCount(source)
        self.delays = (0..<frameCount).map { Self.delay(source: source, index: $0) }

        let size = MediaLoader.pixelSize(of: source) ?? CGSize(width: 1, height: 1)
        self.canvasSize = size
        let frameBytes = Int(size.width * size.height) * 4
        self.cacheAll = frameBytes * frameCount < 500 * 1024 * 1024
    }

    func start() {
        guard !running, frameCount > 1 else { return }
        running = true
        step()
    }

    func stop() {
        running = false
    }

    private func step() {
        guard running else { return }
        let current = index
        let delay = delays[current]

        if let cached = cache[current] {
            targetLayer?.contents = cached
            scheduleNext(after: delay, from: current)
        } else {
            decodeQueue.async { [weak self] in
                guard let self else { return }
                let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
                let image = CGImageSourceCreateImageAtIndex(self.source, current, options)
                DispatchQueue.main.async {
                    guard self.running else { return }
                    if let image {
                        if self.cacheAll { self.cache[current] = image }
                        self.targetLayer?.contents = image
                    }
                    self.scheduleNext(after: delay, from: current)
                }
            }
        }
    }

    private func scheduleNext(after delay: Double, from current: Int) {
        index = (current + 1) % frameCount
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.step()
        }
    }

    private static func delay(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        else { return 0.1 }

        func read(_ dict: CFString, _ unclamped: CFString, _ clamped: CFString) -> Double? {
            guard let d = props[dict] as? [CFString: Any] else { return nil }
            if let v = d[unclamped] as? Double, v > 0 { return v }
            if let v = d[clamped] as? Double, v > 0 { return v }
            return nil
        }

        let value = read(kCGImagePropertyGIFDictionary,
                         kCGImagePropertyGIFUnclampedDelayTime,
                         kCGImagePropertyGIFDelayTime)
            ?? read(kCGImagePropertyWebPDictionary,
                    kCGImagePropertyWebPUnclampedDelayTime,
                    kCGImagePropertyWebPDelayTime)
            ?? read(kCGImagePropertyPNGDictionary,
                    kCGImagePropertyAPNGUnclampedDelayTime,
                    kCGImagePropertyAPNGDelayTime)
            ?? read(kCGImagePropertyHEICSDictionary,
                    kCGImagePropertyHEICSUnclampedDelayTime,
                    kCGImagePropertyHEICSDelayTime)
            ?? 0.1
        return max(value, 0.02)
    }
}
