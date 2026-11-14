import AppKit
import Foundation

// Cette image représente le vrai inventaire compilé. Ce n’est pas une capture de l’app.
let arguments = CommandLine.arguments
guard arguments.count == 3,
      let data = FileManager.default.contents(atPath: arguments[1]),
      let report = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let tree = report["tree"] as? [String] else { fatalError("Inventaire JSON introuvable") }
let lines = ["CADENCE · INVENTAIRE DU BUNDLE", "IPA non signé · test iPhone non effectué", ""] + Array(tree.prefix(65))
let width: CGFloat = 1500
let height = CGFloat(120 + lines.count * 24)
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.15, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
    .foregroundColor: NSColor.white
]
for (index, line) in lines.enumerated() {
    (line as NSString).draw(at: NSPoint(x: 32, y: height - 56 - CGFloat(index * 24)), withAttributes: attributes)
}
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Rendu PNG impossible") }
try png.write(to: URL(fileURLWithPath: arguments[2]))
