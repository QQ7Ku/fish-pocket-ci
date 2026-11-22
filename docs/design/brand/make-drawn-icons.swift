// Draws the alternate app icons that are drawn in code rather than made by an image model: for now
// 小鲸鱼, the Bot "whale" look (app/DshIOS/Views/BotCharacter.swift). This project's own drawing, under MIT.
//
// Each icon gets three pictures: light (opaque, full bleed), dark (transparent, the system's dark
// backdrop shows through) and tinted (white on nothing, which the system tints).
//
// Run from the repository root on a Mac, before make-icons.py (which makes the page previews):
//   xcrun swiftc docs/design/brand/make-drawn-icons.swift -o /tmp/make-drawn-icons && /tmp/make-drawn-icons
import AppKit
import SwiftUI

let catalog = "app/DshIOS/Assets.xcassets/"

// MARK: - Pieces (the same as BotCharacter's Draw)

func polygon(_ points: [(Double, Double)], radius: Double) -> Path {
    let corners = points.map { CGPoint(x: $0.0, y: $0.1) }
    var path = Path()
    let last = corners[corners.count - 1]
    path.move(to: CGPoint(x: (last.x + corners[0].x) / 2, y: (last.y + corners[0].y) / 2))
    for (index, corner) in corners.enumerated() {
        path.addArc(tangent1End: corner, tangent2End: corners[(index + 1) % corners.count], radius: radius)
    }
    path.closeSubpath()
    return path
}

func blob(_ points: [(Double, Double)]) -> Path {
    let knots = points.map { CGPoint(x: $0.0, y: $0.1) }
    let count = knots.count
    var path = Path()
    path.move(to: knots[0])
    for index in 0..<count {
        let before = knots[(index + count - 1) % count], from = knots[index], to = knots[(index + 1) % count], after = knots[(index + 2) % count]
        path.addCurve(to: to,
                      control1: CGPoint(x: from.x + (to.x - before.x) / 6, y: from.y + (to.y - before.y) / 6),
                      control2: CGPoint(x: to.x - (after.x - from.x) / 6, y: to.y - (after.y - from.y) / 6))
    }
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32) -> Color {
    Color(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
}

let whaleBody = blob([(20, 60), (32, 37), (58, 27), (84, 39), (91, 60), (72, 80), (38, 81)])
    .union(polygon([(24, 62), (5, 33), (19, 38), (29, 25), (36, 54)], radius: 4))
let brand = color(0x4D6BFE)
let paleTop = Color(red: 0.95, green: 0.96, blue: 1), paleBottom = Color(red: 0.86, green: 0.89, blue: 1)

enum Look { case light, dark, tinted }

typealias Drawing = (inout GraphicsContext, Look) -> Void

func backdrop(_ context: inout GraphicsContext, _ top: Color, _ bottom: Color) {
    context.fill(Path(CGRect(x: 0, y: 0, width: 100, height: 100)),
                 with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 100)))
}

// MARK: - The icons

/// 小鲸鱼: the Bot whale, with its eyes, on a pale blue page.
let whale: Drawing = { context, look in
    if look == .light { backdrop(&context, paleTop, paleBottom) }
    // The body's own 100-unit box, scaled the way the icon was first drawn (66% of the width).
    let box = whaleBody.boundingRect
    let scale = 66 / box.width
    let transform = CGAffineTransform(translationX: 50, y: 50).scaledBy(x: scale, y: scale).translatedBy(x: -box.midX, y: -box.midY)
    context.fill(whaleBody.applying(transform), with: .color(look == .tinted ? .white : brand))
    let eyes = (x: 64.0, y: 55.0, gap: 18.0, width: 8.5, height: 14.0)
    for side in [-0.5, 0.5] {
        let centre = CGPoint(x: eyes.x + side * eyes.gap, y: eyes.y)
        let socket = Path(roundedRect: CGRect(x: centre.x - eyes.width / 2, y: centre.y - eyes.height / 2, width: eyes.width, height: eyes.height),
                          cornerRadius: eyes.width / 2)
        context.fill(socket.applying(transform), with: .color(look == .tinted ? .black : .white))
        let pupil = eyes.width * 0.62
        let spot = CGPoint(x: centre.x + 0.4 * ((eyes.width - pupil) / 2 - 0.3), y: centre.y)
        context.fill(Path(ellipseIn: CGRect(x: spot.x - pupil / 2, y: spot.y - pupil / 2, width: pupil, height: pupil)).applying(transform),
                     with: .color(look == .tinted ? .white : color(0x141416)))
    }
}

let icons: [(name: String, draw: Drawing)] = [("Whale", whale)]

// MARK: - Output

struct Icon: View {
    let draw: Drawing
    let look: Look

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 100, y: size.height / 100)
            draw(&context, look)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func save(_ draw: @escaping Drawing, _ look: Look, to path: String) {
    let renderer = ImageRenderer(content: Icon(draw: draw, look: look))
    renderer.scale = 1
    // The light icon must have no transparency; the other two are transparent on purpose.
    renderer.isOpaque = look == .light
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("could not draw \(path)") }
    try! png.write(to: URL(fileURLWithPath: path))
}

MainActor.assumeIsolated {
    for icon in icons {
        let folder = catalog + "AppIcon-\(icon.name).appiconset/"
        try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        save(icon.draw, .light, to: folder + "AppIcon.png")
        save(icon.draw, .dark, to: folder + "AppIcon-Dark.png")
        save(icon.draw, .tinted, to: folder + "AppIcon-Tinted.png")
    }
}
