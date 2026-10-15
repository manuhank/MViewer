import AppKit
import QuickLookThumbnailing

/// Gets the strip's thumbnails from Quick Look (rendered out of process and
/// cached on disk by the system), several at a time through a queue the app
/// controls: new requests are held back while the main image's full-resolution
/// decode runs, so thumbnails never compete with what the user is looking at.
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let queue = OperationQueue()
    /// Keyed by scale and path: a 1x thumbnail is blurry on a Retina display.
    private let cache = NSCache<NSString, NSImage>()
    private var mainDecodesInFlight = 0
    private var pendingResume: DispatchWorkItem?

    /// How long the main image must be idle before thumbnails resume, so
    /// flipping through images keeps them out of the way until you stop.
    private static let resumeDelay: TimeInterval = 0.3

    private init() {
        queue.name = "MViewer thumbnails"
        queue.qualityOfService = .utility
        // Leave half the cores for the main image and the UI.
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        // Each thumbnail is ~60 KB at 2x, so at most ~24 MB.
        cache.countLimit = 400
    }

    func cached(_ url: URL, scale: CGFloat) -> NSImage? {
        cache.object(forKey: Self.key(url, scale))
    }

    /// Queues a thumbnail of `size` points. `completion` runs on the main
    /// thread with the thumbnail, or the file's icon if none could be made
    /// (cached too, so failures aren't retried), and not at all if the
    /// returned operation is cancelled first.
    func load(_ url: URL, size: CGSize, scale: CGFloat,
              completion: @escaping (NSImage) -> Void) -> Operation {
        let operation = ThumbnailOperation(url: url, size: size, scale: scale)
        operation.completion = { [cache] image in
            let image = image ?? NSWorkspace.shared.icon(forFile: url.path)
            cache.setObject(image, forKey: Self.key(url, scale))
            completion(image)
        }
        queue.addOperation(operation)
        return operation
    }

    private static func key(_ url: URL, _ scale: CGFloat) -> NSString {
        "\(scale)|\(url.path)" as NSString
    }

    // MARK: - Main image priority

    /// Main thread. While any main image decode is in flight no new thumbnail
    /// request starts; ones already running finish (they are small).
    func mainDecodeStarted() {
        mainDecodesInFlight += 1
        pendingResume?.cancel()
        pendingResume = nil
        queue.isSuspended = true
    }

    /// Main thread. Call exactly once per `mainDecodeStarted()`.
    func mainDecodeFinished() {
        mainDecodesInFlight = max(mainDecodesInFlight - 1, 0)
        guard mainDecodesInFlight == 0 else { return }
        let resume = DispatchWorkItem { [weak self] in
            guard let self, self.mainDecodesInFlight == 0 else { return }
            self.queue.isSuspended = false
        }
        pendingResume = resume
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resumeDelay, execute: resume)
    }
}

/// One Quick Look request as an asynchronous operation, so the queue limits
/// how many run at once and cancelling it cancels the request. If Quick Look
/// fails, falls back to a small ImageIO decode (images only).
private final class ThumbnailOperation: Operation, @unchecked Sendable {
    /// Main thread; set before the operation is queued.
    var completion: ((NSImage?) -> Void)?

    private let url: URL
    private let request: QLThumbnailGenerator.Request
    private let lock = NSLock()
    private var running = false
    private var done = false

    init(url: URL, size: CGSize, scale: CGFloat) {
        self.url = url
        request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale,
                                               representationTypes: .thumbnail)
    }

    override var isAsynchronous: Bool { true }
    override var isExecuting: Bool { lock.withLock { running } }
    override var isFinished: Bool { lock.withLock { done } }

    override func start() {
        guard !isCancelled else { return finish() }
        setState(running: true, done: false)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let self else { return }
            guard !self.isCancelled else { return self.finish() }
            if let image = representation?.nsImage {
                self.deliver(image)
            } else {
                // Quick Look delivers results on one serial queue: decode the
                // fallback elsewhere so it doesn't hold up other thumbnails.
                DispatchQueue.global(qos: .utility).async {
                    self.deliver(self.isCancelled ? nil : self.fallback())
                }
            }
        }
    }

    private func deliver(_ image: NSImage?) {
        DispatchQueue.main.async {
            if !self.isCancelled { self.completion?(image) }
        }
        finish()
    }

    override func cancel() {
        super.cancel()
        QLThumbnailGenerator.shared.cancel(request)
    }

    private func fallback() -> NSImage? {
        guard Media.kind(of: url) == .image else { return nil }
        let maxPixel = max(request.size.width, request.size.height) * request.scale
        return MediaLoader.source(for: url)
            .flatMap { MediaLoader.quickPreview(source: $0, maxPixel: maxPixel) }
            .map { NSImage(cgImage: $0, size: .zero) }
    }

    private func finish() {
        guard !isFinished else { return }
        setState(running: false, done: true)
    }

    private func setState(running: Bool, done: Bool) {
        willChangeValue(forKey: "isExecuting")
        willChangeValue(forKey: "isFinished")
        lock.withLock {
            self.running = running
            self.done = done
        }
        didChangeValue(forKey: "isFinished")
        didChangeValue(forKey: "isExecuting")
    }
}
