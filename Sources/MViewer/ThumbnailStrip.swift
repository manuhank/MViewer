import AppKit
import QuickLookThumbnailing

/// Horizontal strip of the folder's files along the bottom of the window.
/// Built on a virtualized collection view: only visible cells exist, and only
/// they request thumbnails (from Quick Look, which renders out of process and
/// keeps its own disk cache), so large folders cost nothing until scrolled to.
final class ThumbnailStripView: NSView, NSCollectionViewDataSource {
    static let height: CGFloat = 84
    static let thumbnailSize = NSSize(width: 88, height: 62)

    /// Called with the index of the clicked file.
    var onSelect: ((Int) -> Void)?

    private let scrollView = HorizontalScrollView()
    private let collectionView = NSCollectionView()
    private var files: [URL] = []
    private var currentIndex = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: Self.thumbnailSize.width + 6, height: Self.thumbnailSize.height + 6)
        layout.minimumLineSpacing = 4
        layout.sectionInset = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(ThumbnailItem.self, forItemWithIdentifier: ThumbnailItem.identifier)

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
    }

    /// Shows `files`, reloading only if the list changed, and marks `current`.
    func show(files: [URL], current: Int) {
        if files != self.files {
            self.files = files
            currentIndex = current
            collectionView.reloadData()
            collectionView.layoutSubtreeIfNeeded()
        }
        setCurrent(current)
    }

    /// Highlights `index` and scrolls it into view, without reloading.
    func setCurrent(_ index: Int) {
        guard files.indices.contains(index) else { return }
        let previous = currentIndex
        currentIndex = index
        for i in [previous, index] {
            (collectionView.item(at: IndexPath(item: i, section: 0)) as? ThumbnailItem)?.isCurrent = i == index
        }
        collectionView.scrollToItems(at: [IndexPath(item: index, section: 0)],
                                     scrollPosition: .centeredHorizontally)
    }

    // MARK: - NSCollectionViewDataSource

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        files.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ThumbnailItem.identifier, for: indexPath)
        guard let thumbnail = item as? ThumbnailItem else { return item }
        let index = indexPath.item
        thumbnail.configure(url: files[index], scale: window?.backingScaleFactor ?? 2)
        thumbnail.isCurrent = index == currentIndex
        thumbnail.onClick = { [weak self] in self?.onSelect?(index) }
        return thumbnail
    }
}

/// Scroll view that also scrolls sideways with a plain (vertical) mouse wheel.
private final class HorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), let doc = documentView else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
        var origin = contentView.bounds.origin
        origin.x = min(max(origin.x - delta, 0), max(doc.frame.width - contentView.bounds.width, 0))
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}

/// One thumbnail cell. Requests its thumbnail when configured and cancels the
/// request when reused for another file, so scrolled-past cells do no work.
private final class ThumbnailItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailItem")

    var onClick: (() -> Void)?
    var isCurrent = false {
        didSet { frameView.isCurrent = isCurrent }
    }

    private let frameView = ThumbnailFrameView()
    private let thumbnailView = NSImageView()
    private let videoBadge = NSImageView()
    private var url: URL?
    private var request: QLThumbnailGenerator.Request?

    override func loadView() {
        frameView.frame = NSRect(origin: .zero, size: NSSize(width: ThumbnailStripView.thumbnailSize.width + 6,
                                                             height: ThumbnailStripView.thumbnailSize.height + 6))
        thumbnailView.frame = frameView.bounds.insetBy(dx: 3, dy: 3)
        thumbnailView.autoresizingMask = [.width, .height]
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 3
        thumbnailView.layer?.masksToBounds = true
        frameView.addSubview(thumbnailView)

        videoBadge.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Video")
        videoBadge.contentTintColor = .white
        videoBadge.frame = NSRect(x: 7, y: 7, width: 16, height: 16)
        videoBadge.isHidden = true
        frameView.addSubview(videoBadge)

        frameView.onClick = { [weak self] in self?.onClick?() }
        view = frameView
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelRequest()
        thumbnailView.image = nil
        url = nil
        onClick = nil
    }

    func configure(url: URL, scale: CGFloat) {
        self.url = url
        frameView.toolTip = url.lastPathComponent
        frameView.setAccessibilityLabel(url.lastPathComponent)
        videoBadge.isHidden = Media.kind(of: url) != .video

        if let cached = ThumbnailCache.shared.image(for: url) {
            thumbnailView.image = cached
            return
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: ThumbnailStripView.thumbnailSize,
                                                   scale: scale,
                                                   representationTypes: [.lowQualityThumbnail, .thumbnail])
        self.request = request
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { [weak self] representation, type, error in
            DispatchQueue.main.async {
                guard let self, self.url == url else { return }
                if let representation {
                    self.thumbnailView.image = representation.nsImage
                    if type == .thumbnail {
                        ThumbnailCache.shared.set(representation.nsImage, for: url)
                        self.request = nil
                    }
                } else if error != nil, self.thumbnailView.image == nil {
                    self.request = nil
                    self.loadFallback(url: url, scale: scale)
                }
            }
        }
    }

    /// Quick Look occasionally fails (busy, unsupported): decode a small
    /// thumbnail in process instead (embedded preview when present), at low
    /// priority so it never competes with the main image.
    private func loadFallback(url: URL, scale: CGFloat) {
        guard Media.kind(of: url) == .image else {
            thumbnailView.image = NSWorkspace.shared.icon(forFile: url.path)
            return
        }
        let maxPixel = max(ThumbnailStripView.thumbnailSize.width, ThumbnailStripView.thumbnailSize.height) * scale
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = MediaLoader.source(for: url)
                .flatMap { MediaLoader.quickPreview(source: $0, maxPixel: maxPixel) }
                .map { NSImage(cgImage: $0, size: .zero) }
                ?? NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async {
                guard let self, self.url == url else { return }
                self.thumbnailView.image = image
                ThumbnailCache.shared.set(image, for: url)
            }
        }
    }

    private func cancelRequest() {
        if let request { QLThumbnailGenerator.shared.cancel(request) }
        request = nil
    }
}

/// Cell background: rounded frame, accent-colored for the current file.
private final class ThumbnailFrameView: NSView {
    var onClick: (() -> Void)?
    var isCurrent = false {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 2
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderColor = (isCurrent ? NSColor.controlAccentColor : NSColor.clear).cgColor
        layer?.backgroundColor = (isCurrent ? NSColor.white.withAlphaComponent(0.08) : NSColor.clear).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// Finished thumbnails, so scrolling back doesn't ask Quick Look again.
/// Bounded by count; each thumbnail is ~90 KB at 2x, so at most ~35 MB.
private final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 400
    }

    func image(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
    func set(_ image: NSImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}
