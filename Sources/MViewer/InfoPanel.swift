import AppKit
import AVFoundation
import ImageIO
import MapKit

/// Sidebar with file details, image properties, EXIF, GPS, plus a raw dump
/// of every remaining metadata dictionary.
final class InfoSidebarView: NSVisualEffectView {
    var onClose: (() -> Void)?

    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private let mapView = MKMapView()
    private var mapCoordinate: CLLocationCoordinate2D?
    private var currentURL: URL?
    private var videoTask: Task<Void, Never>?

    private static let headerHeight: CGFloat = 34
    private static let mapHeight: CGFloat = 180

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        material = .sidebar
        blendingMode = .behindWindow
        state = .followsWindowActiveState

        let title = NSTextField(labelWithString: "Info")
        title.font = .systemFont(ofSize: 13, weight: .bold)
        title.sizeToFit()
        title.frame.origin = NSPoint(x: 12, y: bounds.height - 24)
        title.autoresizingMask = [.minYMargin]
        addSubview(title)

        let close = NSButton()
        close.image = NSImage(systemSymbolName: "xmark.circle.fill",
                              accessibilityDescription: "Close info sidebar")
        close.isBordered = false
        close.bezelStyle = .regularSquare
        close.contentTintColor = .secondaryLabelColor
        close.target = self
        close.action = #selector(closePressed)
        close.frame = NSRect(x: bounds.width - 30, y: bounds.height - 27, width: 20, height: 20)
        close.autoresizingMask = [.minXMargin, .minYMargin]
        addSubview(close)

        mapView.frame = NSRect(x: 0, y: bounds.height - Self.headerHeight - Self.mapHeight,
                               width: bounds.width, height: Self.mapHeight)
        mapView.autoresizingMask = [.width, .minYMargin]
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.isHidden = true
        let mapClick = NSClickGestureRecognizer(target: self, action: #selector(openInMaps))
        mapView.addGestureRecognizer(mapClick)
        addSubview(mapView)

        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width,
                              height: bounds.height - Self.headerHeight)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        textView.frame = scroll.bounds
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func closePressed() {
        onClose?()
    }

    @objc private func openInMaps() {
        guard let coordinate = mapCoordinate else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = currentURL?.lastPathComponent ?? "Photo"
        item.openInMaps()
    }

    private func updateMap(for url: URL) {
        mapCoordinate = InfoFormatter.gpsCoordinate(url: url)
        if let coordinate = mapCoordinate {
            mapView.removeAnnotations(mapView.annotations)
            let pin = MKPointAnnotation()
            pin.coordinate = coordinate
            pin.title = url.lastPathComponent
            mapView.addAnnotation(pin)
            mapView.setRegion(MKCoordinateRegion(center: coordinate,
                                                 latitudinalMeters: 2000,
                                                 longitudinalMeters: 2000),
                              animated: false)
            mapView.isHidden = false
        } else {
            mapView.isHidden = true
        }
        let mapSpace = mapView.isHidden ? 0 : Self.mapHeight
        scroll.frame = NSRect(x: 0, y: 0, width: bounds.width,
                              height: bounds.height - Self.headerHeight - mapSpace)
    }

    func render(url: URL) {
        currentURL = url
        videoTask?.cancel()
        updateMap(for: url)
        textView.textStorage?.setAttributedString(InfoFormatter.build(url: url, videoRows: nil))
        textView.scroll(.zero)

        if Media.kind(of: url) == .video {
            videoTask = Task { [weak self] in
                let rows = await InfoFormatter.videoRows(url: url)
                guard !Task.isCancelled, let self, self.currentURL == url else { return }
                self.textView.textStorage?.setAttributedString(
                    InfoFormatter.build(url: url, videoRows: rows))
            }
        }
    }
}

enum InfoFormatter {

    // MARK: - Attributed string assembly

    private static let headerAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .bold),
        .foregroundColor: NSColor.labelColor,
    ]
    private static let keyAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]
    private static let valueAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.labelColor,
    ]

    static func build(url: URL, videoRows: [(String, String)]?) -> NSAttributedString {
        let out = NSMutableAttributedString()

        appendSection(out, title: "File", rows: fileRows(url: url))

        if Media.kind(of: url) == .image,
           let source = MediaLoader.source(for: url),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            appendSection(out, title: "Image", rows: imageRows(props: props, source: source))
            appendSection(out, title: "Camera / EXIF", rows: exifRows(props: props))
            appendSection(out, title: "GPS", rows: gpsRows(props: props))
            appendSection(out, title: "All Metadata", rows: rawRows(props: props))
        }

        if let videoRows {
            appendSection(out, title: "Video", rows: videoRows)
        } else if Media.kind(of: url) == .video {
            appendSection(out, title: "Video", rows: [("Status", "Loading…")])
        }

        return out
    }

    private static func appendSection(_ out: NSMutableAttributedString,
                                      title: String, rows: [(String, String)]) {
        guard !rows.isEmpty else { return }
        if out.length > 0 {
            out.append(NSAttributedString(string: "\n", attributes: valueAttrs))
        }
        out.append(NSAttributedString(string: title + "\n", attributes: headerAttrs))
        let keyWidth = min(rows.map { $0.0.count }.max() ?? 0, 26)
        for (key, value) in rows {
            let padded = key.padding(toLength: max(keyWidth, key.count), withPad: " ", startingAt: 0)
            out.append(NSAttributedString(string: "  " + padded + "  ", attributes: keyAttrs))
            out.append(NSAttributedString(string: value + "\n", attributes: valueAttrs))
        }
    }

    // MARK: - Sections

    private static func fileRows(url: URL) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Name", url.lastPathComponent),
            ("Folder", url.deletingLastPathComponent().path),
        ]
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let size = attrs[.size] as? Int64 {
                let human = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                rows.append(("Size", "\(human)  (\(size) bytes)"))
            }
            if let created = attrs[.creationDate] as? Date {
                rows.append(("Created", format(date: created)))
            }
            if let modified = attrs[.modificationDate] as? Date {
                rows.append(("Modified", format(date: modified)))
            }
        }
        return rows
    }

    private static func imageRows(props: [CFString: Any], source: CGImageSource) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let w = props[kCGImagePropertyPixelWidth] as? Int,
           let h = props[kCGImagePropertyPixelHeight] as? Int {
            let mp = Double(w * h) / 1_000_000
            rows.append(("Dimensions", "\(w) × \(h)  (\(String(format: "%.1f", mp)) MP)"))
        }
        if let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 0 {
            rows.append(("Resolution", "\(Int(dpi)) dpi"))
        }
        if let depth = props[kCGImagePropertyDepth] as? Int {
            rows.append(("Bit Depth", "\(depth)-bit"))
        }
        if let model = props[kCGImagePropertyColorModel] as? String {
            rows.append(("Color Model", model))
        }
        if let profile = props[kCGImagePropertyProfileName] as? String {
            rows.append(("Color Profile", profile))
        }
        if let orientation = props[kCGImagePropertyOrientation] as? Int, orientation != 1 {
            rows.append(("Orientation", "\(orientation)"))
        }
        let frames = CGImageSourceGetCount(source)
        if frames > 1 {
            rows.append(("Frames", "\(frames)"))
        }
        if let alpha = props[kCGImagePropertyHasAlpha] as? Bool, alpha {
            rows.append(("Alpha", "yes"))
        }
        return rows
    }

    private static func exifRows(props: [CFString: Any]) -> [(String, String)] {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        var rows: [(String, String)] = []

        let make = tiff[kCGImagePropertyTIFFMake] as? String
        let model = tiff[kCGImagePropertyTIFFModel] as? String
        if make != nil || model != nil {
            rows.append(("Camera", [make, model].compactMap { $0 }.joined(separator: " ")))
        }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String {
            rows.append(("Lens", lens))
        }
        if let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            rows.append(("Taken", date))
        }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            let shutter = t < 1 ? "1/\(Int((1 / t).rounded())) s" : String(format: "%.1f s", t)
            rows.append(("Shutter", shutter))
        }
        if let f = exif[kCGImagePropertyExifFNumber] as? Double {
            rows.append(("Aperture", String(format: "ƒ/%.1f", f)))
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
            rows.append(("ISO", "\(iso)"))
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
            var text = String(format: "%.0f mm", focal)
            if let eq = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int {
                text += "  (\(eq) mm eq.)"
            }
            rows.append(("Focal Length", text))
        }
        if let bias = exif[kCGImagePropertyExifExposureBiasValue] as? Double, bias != 0 {
            rows.append(("Exposure Bias", String(format: "%+.1f EV", bias)))
        }
        if let flash = exif[kCGImagePropertyExifFlash] as? Int {
            rows.append(("Flash", flash & 1 == 1 ? "fired" : "did not fire"))
        }
        if let software = tiff[kCGImagePropertyTIFFSoftware] as? String {
            rows.append(("Software", software))
        }
        return rows
    }

    /// Signed coordinate from the image's GPS metadata, if present.
    static func gpsCoordinate(url: URL) -> CLLocationCoordinate2D? {
        guard Media.kind(of: url) == .image,
              let source = MediaLoader.source(for: url),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              var lon = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private static func gpsRows(props: [CFString: Any]) -> [(String, String)] {
        guard let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] else { return [] }
        var rows: [(String, String)] = []
        if let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            rows.append(("Position", String(format: "%.6f° %@, %.6f° %@", lat, latRef, lon, lonRef)))
        }
        if let alt = gps[kCGImagePropertyGPSAltitude] as? Double {
            rows.append(("Altitude", String(format: "%.0f m", alt)))
        }
        return rows
    }

    /// Flattens every metadata dictionary into "Dict.Key  value" rows.
    private static func rawRows(props: [CFString: Any]) -> [(String, String)] {
        var rows: [(String, String)] = []
        flatten(props, prefix: "", into: &rows)
        return rows.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    private static func flatten(_ dict: [CFString: Any], prefix: String,
                                into rows: inout [(String, String)]) {
        for (key, value) in dict {
            let name = prefix.isEmpty ? String(key) : "\(prefix).\(key)"
            if let nested = value as? [CFString: Any] {
                flatten(nested, prefix: cleaned(name), into: &rows)
            } else {
                var text = "\(value)".replacingOccurrences(of: "\n", with: " ")
                if text.count > 120 { text = String(text.prefix(120)) + "…" }
                rows.append((cleaned(name), text))
            }
        }
    }

    /// Strips the "{Exif}"-style braces ImageIO uses for dictionary keys.
    private static func cleaned(_ key: String) -> String {
        key.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
    }

    // MARK: - Video

    static func videoRows(url: URL) async -> [(String, String)] {
        let asset = AVURLAsset(url: url)
        var rows: [(String, String)] = []
        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            rows.append(("Duration", format(seconds: seconds)))
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                let rect = CGRect(origin: .zero, size: size).applying(transform)
                rows.append(("Dimensions", "\(Int(abs(rect.width))) × \(Int(abs(rect.height)))"))
            }
            if let fps = try? await track.load(.nominalFrameRate), fps > 0 {
                rows.append(("Frame Rate", String(format: "%.2f fps", fps)))
            }
            if let rate = try? await track.load(.estimatedDataRate), rate > 0 {
                rows.append(("Bit Rate", String(format: "%.1f Mbit/s", rate / 1_000_000)))
            }
            if let descriptions = try? await track.load(.formatDescriptions),
               let desc = descriptions.first {
                let code = CMFormatDescriptionGetMediaSubType(desc)
                rows.append(("Codec", fourCC(code)))
            }
        }
        if let audio = try? await asset.loadTracks(withMediaType: .audio).first,
           let descriptions = try? await audio.load(.formatDescriptions),
           let desc = descriptions.first {
            rows.append(("Audio", fourCC(CMFormatDescriptionGetMediaSubType(desc))))
        }
        return rows
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }

    // MARK: - Formatting

    private static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func format(seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
