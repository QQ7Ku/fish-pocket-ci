// Cuts the subject out of the painted icons (the mascot, the sticker, the geometric whale) with the
// system's subject lifting, so make-icons.py can give them a dark and a tinted picture: the dark one
// drops the light background and lets the system's dark backdrop show; the tinted one keeps only the
// subject for the system to tint.
//
// The masks are kept in masks/ because the cut can change between macOS versions. Run again only
// when one of the pictures changes, from the repository root on a Mac, before make-icons.py:
//   xcrun swiftc docs/design/brand/make-subject-masks.swift -o /tmp/make-subject-masks && /tmp/make-subject-masks
import CoreImage
import Foundation
import Vision

let brand = "docs/design/brand/"

for (source, name) in [("mascot-icon.png", "mascot"), ("generated/sticker.png", "sticker"), ("generated/geometric.png", "geometric")] {
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: brand + source))
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])
    guard let subject = request.results?.first else { fatalError("No subject found in \(source)") }
    let mask = try subject.generateScaledMaskForImage(forInstances: subject.allInstances, from: handler)
    try CIContext().writePNGRepresentation(of: CIImage(cvPixelBuffer: mask),
                                           to: URL(fileURLWithPath: brand + "masks/\(name).png"),
                                           format: .L8, colorSpace: CGColorSpace(name: CGColorSpace.linearGray)!)
}
