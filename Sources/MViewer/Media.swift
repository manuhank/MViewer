import Foundation

enum Media {
    enum Kind {
        case image
        case video
    }

    static let imageExtensions: Set<String> = [
        // common
        "jpg", "jpeg", "jpe", "png", "gif", "webp", "bmp", "ico", "icns",
        "tif", "tiff", "heic", "heif", "heics", "avif", "jp2", "j2k", "jpf",
        "psd", "exr", "hdr", "tga", "sgi", "pbm", "pgm", "ppm", "pnm", "pic",
        // camera raw
        "nef", "nrw", "arw", "sr2", "srf", "cr2", "cr3", "crw", "raf", "orf",
        "rw2", "dng", "srw", "pef", "erf", "kdc", "mrw", "rwl", "x3f", "3fr",
        "fff", "iiq", "mos", "mef", "dcr",
    ]

    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "qt", "3gp", "3g2", "mts", "m2ts",
    ]

    // Formats where a frame count > 1 means animation.
    static let animatableExtensions: Set<String> = ["gif", "webp", "png", "apng", "heics"]

    static func kind(of url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        return nil
    }

    static func isSupported(_ url: URL) -> Bool {
        kind(of: url) != nil
    }

    static func isAnimatable(_ url: URL) -> Bool {
        animatableExtensions.contains(url.pathExtension.lowercased())
    }
}
