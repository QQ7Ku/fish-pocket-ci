// Draws the wordmark app icons: "Fish / Pocket" set in type, flat colours only. Where the name is
// in lower case, the dot of the i is a whale's flukes. This project's own drawing, under MIT.
//
//   像素字标  FISH / POCKET in Geist Pixel (Square), pale cyan on navy, like the pixel whale.
//   海报字标  FISH / POCKET in Noto Sans at its narrowest and heaviest, both lines the same width.
//   终端字标  fish / pocket in JetBrains Mono with a block cursor, like a shell waiting for input.
//
// The fonts are all under the SIL Open Font License and are not kept here; get them from their
// own releases (github.com/vercel/geist-font, github.com/notofonts/latin-greek-cyrillic,
// github.com/JetBrains/JetBrainsMono). Noto Sans must be the variable one (width and weight axes);
// for the others a static bold file works as well as a variable one.
//
// Run from the repository root on a Mac, before make-icons.py (which makes the page previews):
//   xcrun swiftc docs/design/brand/make-wordmark-icons.swift -o /tmp/make-wordmark-icons
//   /tmp/make-wordmark-icons <Geist Pixel Square> <Noto Sans variable> <JetBrains Mono>
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let catalog = "app/DshIOS/Assets.xcassets/"

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

/// The font, with its variation axes (by tag, like "wght") set where it has them.
func font(_ path: String, axes: [String: CGFloat] = [:]) -> CTFont {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          var descriptor = (CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor])?.first else {
        fatalError("cannot read the font at \(path)")
    }
    let plain = CTFontCreateWithFontDescriptor(descriptor, 100, nil)
    for axis in (CTFontCopyVariationAxes(plain) as? [[String: Any]]) ?? [] {
        guard let id = axis[kCTFontVariationAxisIdentifierKey as String] as? NSNumber else { continue }
        let tag = String(decoding: withUnsafeBytes(of: id.uint32Value.bigEndian, Array.init), as: UTF8.self)
        if let value = axes[tag] { descriptor = CTFontDescriptorCreateCopyWithVariation(descriptor, id, value) }
    }
    return CTFontCreateWithFontDescriptor(descriptor, 100, nil)
}

/// The subpaths of a path, each on its own.
func pieces(_ path: CGPath) -> [CGPath] {
    var result: [CGMutablePath] = []
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        switch element.type {
        case .moveToPoint: result.append(CGMutablePath()); result.last!.move(to: element.points[0])
        case .addLineToPoint: result.last!.addLine(to: element.points[0])
        case .addQuadCurveToPoint: result.last!.addQuadCurve(to: element.points[1], control: element.points[0])
        case .addCurveToPoint: result.last!.addCurve(to: element.points[2], control1: element.points[0], control2: element.points[1])
        case .closeSubpath: result.last!.closeSubpath()
        @unknown default: break
        }
    }
    return result
}

/// A whale's flukes, y up, 58 units wide, centred on x 50, the stalk standing on y 0.
let flukes: CGPath = {
    let corners: [CGPoint] = [(50, 18), (58, 23), (67, 26), (79, 28), (75, 20), (67, 13), (57.5, 8), (56.5, 0), (43.5, 0), (42.5, 8),
                              (33, 13), (25, 20), (21, 28), (33, 26), (42, 23)].map { CGPoint(x: $0.0, y: $0.1) }
    let path = CGMutablePath()
    let last = corners[corners.count - 1]
    path.move(to: CGPoint(x: (last.x + corners[0].x) / 2, y: (last.y + corners[0].y) / 2))
    for (index, corner) in corners.enumerated() {
        path.addArc(tangent1End: corner, tangent2End: corners[(index + 1) % corners.count], radius: 2.5)
    }
    path.closeSubpath()
    return path
}()

/// One line set at size 100, its pen starting at x 0 on baseline 0. A lower-case i's dot comes back
/// as `tail`: whale's flukes standing where it stood, about two and a half times as wide.
func set(_ text: String, in font: CTFont) -> (letters: CGPath, tail: CGPath) {
    let letters = CGMutablePath(), tail = CGMutablePath()
    // No ligatures: an "fi" ligature has no i of its own to take the dot from.
    let attributes: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font, kCTLigatureAttributeName as NSAttributedString.Key: 0]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let characters = Array(text.utf16)
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run), all = CFRange(location: 0, length: count)
        var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count), indices = [CFIndex](repeating: 0, count: count)
        CTRunGetGlyphs(run, all, &glyphs)
        CTRunGetPositions(run, all, &positions)
        CTRunGetStringIndices(run, all, &indices)
        for index in 0..<count {
            guard let outline = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
            let move = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
            guard characters[indices[index]] == UInt16(UInt8(ascii: "i")) else {
                letters.addPath(outline, transform: move)
                continue
            }
            let parts = pieces(outline).sorted { $0.boundingBox.minY < $1.boundingBox.minY }
            for part in parts.dropLast() { letters.addPath(part, transform: move) }
            let dot = parts.last!.boundingBox
            let scale = dot.width * 2.6 / 58
            tail.addPath(flukes, transform: CGAffineTransform(translationX: positions[index].x + dot.midX, y: dot.minY)
                .scaledBy(x: scale, y: scale).translatedBy(x: -50, y: 0))
        }
    }
    return (letters, tail)
}

struct Colors {
    /// nil leaves the picture transparent: the dark and tinted icons, where the system draws the backdrop.
    let background: CGColor?
    let first: CGColor
    let second: CGColor
    /// The flukes and the cursor.
    let accent: CGColor
}

struct Icon {
    let name: String
    let font: CTFont
    let lines: (String, String)
    /// From the first baseline to the second, at size 100.
    let leading: CGFloat
    /// Both lines scaled to the same width, the second one growing taller.
    var justified = false
    var cursor = false
    /// How much of the icon's width the wordmark takes.
    let width: CGFloat
    let light: Colors
    let dark: Colors
    let tinted: Colors
}

func draw(_ icon: Icon, _ colors: Colors, to path: String) {
    let side = 1024
    guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: (colors.background == nil ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue) else { fatalError("no context") }
    if let background = colors.background {
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
    let first = set(icon.lines.0, in: icon.font), second = set(icon.lines.1, in: icon.font)
    // Each line starts at its own ink, so the block's left edge is straight.
    let firstBox = first.letters.boundingBox, secondBox = second.letters.boundingBox
    var firstPlace = CGAffineTransform(translationX: -firstBox.minX, y: 0)
    var secondPlace = CGAffineTransform(translationX: -secondBox.minX, y: -icon.leading)
    if icon.justified {
        let width = max(firstBox.width, secondBox.width)
        let firstScale = width / firstBox.width, secondScale = width / secondBox.width
        firstPlace = CGAffineTransform(scaleX: firstScale, y: firstScale).translatedBy(x: -firstBox.minX, y: 0)
        // The gap between the lines stays what it was at the first line's size.
        let gap = icon.leading - secondBox.maxY
        secondPlace = CGAffineTransform(translationX: 0, y: firstBox.minY * firstScale - gap * firstScale - secondBox.maxY * secondScale)
            .scaledBy(x: secondScale, y: secondScale).translatedBy(x: -secondBox.minX, y: 0)
    }
    let firstLetters = CGMutablePath(), secondLetters = CGMutablePath(), tail = CGMutablePath()
    firstLetters.addPath(first.letters, transform: firstPlace)
    secondLetters.addPath(second.letters, transform: secondPlace)
    tail.addPath(first.tail, transform: firstPlace)
    tail.addPath(second.tail, transform: secondPlace)
    var box = firstLetters.boundingBox.union(secondLetters.boundingBox)
    if !tail.isEmpty { box = box.union(tail.boundingBox) }
    var cursor: CGRect?
    if icon.cursor {
        let block = CGRect(x: secondLetters.boundingBox.maxX + 10, y: -icon.leading, width: 34, height: CTFontGetXHeight(icon.font))
        cursor = block
        box = box.union(block)
    }
    let scale = CGFloat(side) * icon.width / box.width
    context.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -box.midX, y: -box.midY)
    for (path, ink) in [(firstLetters, colors.first), (secondLetters, colors.second), (tail, colors.accent)] {
        context.setFillColor(ink)
        context.addPath(path)
        context.fillPath()
    }
    if let cursor {
        context.setFillColor(colors.accent)
        context.fill(cursor)
    }
    guard let image = context.makeImage(),
          let file = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("cannot write \(path)") }
    CGImageDestinationAddImage(file, image, nil)
    guard CGImageDestinationFinalize(file) else { fatalError("cannot write \(path)") }
}

guard CommandLine.arguments.count == 4 else {
    print("usage: make-wordmark-icons <Geist Pixel Square> <Noto Sans variable> <JetBrains Mono>")
    exit(1)
}
let pixel = font(CommandLine.arguments[1])
let condensed = font(CommandLine.arguments[2], axes: ["wght": 900, "wdth": 62.5])
let mono = font(CommandLine.arguments[3], axes: ["wght": 700])

let black = color(0x0F0F11), white = color(0xFFFFFF), navy = color(0x0B1236), cyan = color(0x9FE7FF)
let pale = color(0x8EA2FF), grey = color(0xB3B3B3)

let icons = [
    Icon(name: "WordPixel", font: pixel, lines: ("FISH", "POCKET"), leading: 100, width: 0.66,
         light: Colors(background: navy, first: cyan, second: cyan, accent: cyan),
         dark: Colors(background: nil, first: cyan, second: cyan, accent: cyan),
         tinted: Colors(background: nil, first: white, second: white, accent: white)),
    Icon(name: "WordPoster", font: condensed, lines: ("FISH", "POCKET"), leading: 90, justified: true, width: 0.6,
         light: Colors(background: black, first: white, second: pale, accent: pale),
         dark: Colors(background: nil, first: white, second: pale, accent: pale),
         tinted: Colors(background: nil, first: white, second: grey, accent: grey)),
    Icon(name: "WordMono", font: mono, lines: ("fish", "pocket"), leading: 100, cursor: true, width: 0.67,
         light: Colors(background: black, first: white, second: white, accent: pale),
         dark: Colors(background: nil, first: white, second: white, accent: pale),
         tinted: Colors(background: nil, first: white, second: white, accent: grey)),
]

for icon in icons {
    let folder = catalog + "AppIcon-\(icon.name).appiconset/"
    try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    draw(icon, icon.light, to: folder + "AppIcon.png")
    draw(icon, icon.dark, to: folder + "AppIcon-Dark.png")
    draw(icon, icon.tinted, to: folder + "AppIcon-Tinted.png")
}
