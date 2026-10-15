import AppKit

/// Horizontal strip of the folder's files along the bottom of the window.
/// Built on a virtualized collection view: only visible cells exist, and only
/// they queue thumbnails (see `ThumbnailLoader`), so large folders cost
/// nothing until scrolled to.
final class ThumbnailStripView: NSView, NSCollectionViewDataSource {
    static let height: CGFloat = 70
    static let thumbnailSize = NSSize(width: 72, height: 50)
    static let cellSize = NSSize(width: thumbnailSize.width + 6, height: thumbnailSize.height + 6)

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
        layout.itemSize = Self.cellSize
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

/// One thumbnail cell. Queues its thumbnail when configured and cancels it
/// when reused for another file, so scrolled-past cells do no work.
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
    private var operation: Operation?

    override func loadView() {
        frameView.frame = NSRect(origin: .zero, size: ThumbnailStripView.cellSize)
        thumbnailView.frame = frameView.bounds.insetBy(dx: 3, dy: 3)
        thumbnailView.autoresizingMask = [.width, .height]
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 3
        thumbnailView.layer?.masksToBounds = true
        frameView.addSubview(thumbnailView)

        videoBadge.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Video")
        videoBadge.contentTintColor = .white
        videoBadge.frame = NSRect(x: 6, y: 6, width: 14, height: 14)
        videoBadge.isHidden = true
        frameView.addSubview(videoBadge)

        frameView.onClick = { [weak self] in self?.onClick?() }
        view = frameView
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        operation?.cancel()
        operation = nil
        thumbnailView.image = nil
        url = nil
        onClick = nil
    }

    func configure(url: URL, scale: CGFloat) {
        self.url = url
        frameView.toolTip = url.lastPathComponent
        frameView.setAccessibilityLabel(url.lastPathComponent)
        videoBadge.isHidden = Media.kind(of: url) != .video

        if let cached = ThumbnailLoader.shared.cached(url) {
            thumbnailView.image = cached
            return
        }
        operation = ThumbnailLoader.shared.load(url, size: ThumbnailStripView.thumbnailSize,
                                                scale: scale) { [weak self] image in
            guard let self, self.url == url else { return }
            self.operation = nil
            self.thumbnailView.image = image ?? NSWorkspace.shared.icon(forFile: url.path)
        }
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
