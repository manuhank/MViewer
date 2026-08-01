// Renders the app icon (mountains + sun on a dark rounded square) at every
// size required by an .iconset. Run: swift scripts/make_icon.swift <output-dir>
import AppKit
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let u = s / 1024

    // Apple icon grid: 824pt content square centered on a 1024 canvas.
    let rect = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let radius = 824 * u * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    let colors = [
        CGColor(red: 0.17, green: 0.22, blue: 0.33, alpha: 1),
        CGColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: .zero, options: [])

    // Sun with a soft glow.
    let sunCenter = CGPoint(x: 645 * u, y: 645 * u)
    let sunR = 92 * u
    ctx.setFillColor(CGColor(red: 1.0, green: 0.74, blue: 0.28, alpha: 0.25))
    ctx.fillEllipse(in: CGRect(x: sunCenter.x - sunR * 1.5, y: sunCenter.y - sunR * 1.5,
                               width: sunR * 3, height: sunR * 3))
    ctx.setFillColor(CGColor(red: 1.0, green: 0.74, blue: 0.28, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: sunCenter.x - sunR, y: sunCenter.y - sunR,
                               width: sunR * 2, height: sunR * 2))

    // Back mountain.
    ctx.setFillColor(CGColor(red: 0.42, green: 0.49, blue: 0.64, alpha: 1))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 100 * u, y: 100 * u))
    ctx.addLine(to: CGPoint(x: 425 * u, y: 570 * u))
    ctx.addLine(to: CGPoint(x: 710 * u, y: 100 * u))
    ctx.closePath()
    ctx.fillPath()

    // Front mountain.
    ctx.setFillColor(CGColor(red: 0.24, green: 0.29, blue: 0.42, alpha: 1))
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 340 * u, y: 100 * u))
    ctx.addLine(to: CGPoint(x: 655 * u, y: 470 * u))
    ctx.addLine(to: CGPoint(x: 924 * u, y: 100 * u))
    ctx.closePath()
    ctx.fillPath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in specs {
    writePNG(render(size), to: iconset.appendingPathComponent(name + ".png"))
}
print("Wrote \(iconset.path)")
