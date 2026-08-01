import AppKit

/// Keeps the document view centered when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if doc.frame.width < rect.width {
            rect.origin.x = doc.frame.minX - (rect.width - doc.frame.width) / 2
        }
        if doc.frame.height < rect.height {
            rect.origin.y = doc.frame.minY - (rect.height - doc.frame.height) / 2
        }
        return rect
    }
}

/// Scroll view with ⌘+scroll-wheel zoom on top of the built-in pinch zoom.
final class ZoomScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let doc = documentView else {
            super.scrollWheel(with: event)
            return
        }
        let factor = pow(1.003, Double(event.scrollingDeltaY))
        let point = doc.convert(event.locationInWindow, from: nil)
        setMagnification(magnification * factor, centeredAt: point)
    }
}

/// Layer-backed view whose frame is the image's pixel size; the layer's
/// contents can be swapped from a blurry preview to the full decode without
/// touching zoom/scroll state.
final class ImageDocumentView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        layer?.minificationFilter = .trilinear
    }

    required init?(coder: NSCoder) { fatalError() }

    var contentLayer: CALayer { layer! }

    func setImage(_ image: CGImage?, pixelSize: CGSize) {
        layer?.contents = image
        setFrameSize(pixelSize == .zero ? CGSize(width: 1, height: 1) : pixelSize)
    }

    func updateContents(_ image: CGImage) {
        layer?.contents = image
    }
}

/// Vertical strip on the sidebar's left edge that drags to resize it.
/// Draws a hairline divider (highlighted on hover) as the grab affordance.
final class SidebarResizeHandle: NSView {
    /// Reports the pointer's x position in superview coordinates while dragging.
    var onDrag: ((CGFloat) -> Void)?

    private var hovering = false

    override var frame: NSRect {
        didSet { updateTracking() }
    }

    private func updateTracking() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            NSColor.controlAccentColor.withAlphaComponent(0.8).setFill()
            NSRect(x: bounds.midX - 1.5, y: 0, width: 3, height: bounds.height).fill()
        } else {
            NSColor.separatorColor.setFill()
            NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        onDrag?(superview.convert(event.locationInWindow, from: nil).x)
    }
}

/// Content container that accepts file drops.
final class DropContainerView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.filter { Media.isSupported($0) || $0.hasDirectoryPath }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
