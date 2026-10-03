import AppKit
import Foundation

let manager = FileManager.default
let output = URL(fileURLWithPath: manager.currentDirectoryPath).appendingPathComponent("work/MissEnv.iconset")
try manager.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int, name: String) throws {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let body = NSBezierPath(roundedRect: NSRect(x: 88, y: 88, width: 848, height: 848), xRadius: 186, yRadius: 186)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.19, alpha: 1).setFill()
    body.fill()
    NSShadow().set()
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.41, blue: 0.29, alpha: 1), NSColor(calibratedRed: 0.07, green: 0.21, blue: 0.15, alpha: 1)])!.draw(in: body, angle: 90)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let braceAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 400, weight: .light), .foregroundColor: NSColor(calibratedRed: 0.84, green: 0.94, blue: 0.86, alpha: 1), .paragraphStyle: paragraph]
    ("{ }" as NSString).draw(in: NSRect(x: 145, y: 304, width: 734, height: 450), withAttributes: braceAttributes)
    NSColor(calibratedRed: 0.64, green: 0.84, blue: 0.49, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 477, y: 498, width: 70, height: 70)).fill()
    let labelAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 99, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.9), .paragraphStyle: paragraph]
    (".env" as NSString).draw(in: NSRect(x: 160, y: 231, width: 704, height: 126), withAttributes: labelAttributes)
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name))
}
for size in [16, 32, 128, 256, 512] {
    try render(size: size, name: "icon_\(size)x\(size).png")
    try render(size: size * 2, name: "icon_\(size)x\(size)@2x.png")
}
