import Foundation
import ImageIO
import CoreGraphics

enum MediaLoader {
    /// Longest side cap for the full-resolution decode, to keep memory bounded
    /// on gigantic panoramas while still allowing deep zoom.
    static let fullDecodeCap: CGFloat = 12000

    static func source(for url: URL) -> CGImageSource? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        return CGImageSourceCreateWithURL(url as CFURL, options)
    }

    /// Reads the pixel size from the header without decoding, orientation-corrected.
    static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }
        if let o = props[kCGImagePropertyOrientation] as? UInt32, (5...8).contains(o) {
            return CGSize(width: h, height: w)
        }
        return CGSize(width: w, height: h)
    }

    /// Instant preview: uses the embedded thumbnail when present (RAW/JPEG),
    /// otherwise downsamples. Never decodes above `maxPixel`.
    static func quickPreview(source: CGImageSource, maxPixel: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Full decode (orientation applied), capped at `fullDecodeCap` on the longest side.
    static func fullImage(url: URL) -> CGImage? {
        guard let source = source(for: url) else { return nil }
        let native = pixelSize(of: source) ?? CGSize(width: fullDecodeCap, height: fullDecodeCap)
        let maxSide = min(max(native.width, native.height), fullDecodeCap)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Small in-memory cache so navigating back/forward is instant.
final class ImageCache {
    static let shared = ImageCache()

    private let previews = NSCache<NSURL, CGImage>()
    private let fulls = NSCache<NSURL, CGImage>()
    private var inFlight = Set<URL>()
    private let lock = NSLock()

    private init() {
        previews.countLimit = 48
        fulls.countLimit = 6
        fulls.totalCostLimit = 900 * 1024 * 1024
    }

    func preview(for url: URL) -> CGImage? { previews.object(forKey: url as NSURL) }
    func full(for url: URL) -> CGImage? { fulls.object(forKey: url as NSURL) }

    func setPreview(_ image: CGImage, for url: URL) {
        previews.setObject(image, forKey: url as NSURL)
    }

    func setFull(_ image: CGImage, for url: URL) {
        fulls.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
    }

    /// Decodes a preview in the background unless one is cached or already being decoded.
    func prefetchPreview(for url: URL, maxPixel: CGFloat) {
        guard Media.kind(of: url) == .image, preview(for: url) == nil else { return }
        lock.lock()
        guard !inFlight.contains(url) else { lock.unlock(); return }
        inFlight.insert(url)
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer {
                self?.lock.lock()
                self?.inFlight.remove(url)
                self?.lock.unlock()
            }
            guard let source = MediaLoader.source(for: url),
                  let image = MediaLoader.quickPreview(source: source, maxPixel: maxPixel)
            else { return }
            self?.setPreview(image, for: url)
        }
    }
}
