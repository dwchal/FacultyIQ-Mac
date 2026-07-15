// Renders the FacultyIQ app icon (a coauthorship-network motif on the app's
// series-1 blue) as a 1024x1024 PNG. Regenerate AppIcon.icns with:
//   swift scripts/make-icon.swift /tmp/icon_1024.png
//   then sips/iconutil (see scripts/build-icon.sh)
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let canvas: CGFloat = 1024
// macOS icon grid: artwork sits in a rounded square inset from the canvas.
let inset: CGFloat = 100
let content = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// Background: rounded square, top-lit blue gradient (ChartPalette series1 family).
let corner = content.width * 0.225
let square = NSBezierPath(roundedRect: content, xRadius: corner, yRadius: corner)
NSGradient(
    starting: NSColor(srgbRed: 0x39 / 255, green: 0x87 / 255, blue: 0xE5 / 255, alpha: 1),
    ending: NSColor(srgbRed: 0x16 / 255, green: 0x4E / 255, blue: 0x96 / 255, alpha: 1)
)!.draw(in: square, angle: -90)

// Network glyph: five nodes, hub-and-spoke plus one cross edge, all white.
// Positions are unit coordinates within the content square (y up).
func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
    NSPoint(x: content.minX + x * content.width, y: content.minY + y * content.height)
}
let hub = point(0.50, 0.46)
let satellites = [point(0.24, 0.71), point(0.76, 0.74), point(0.21, 0.28), point(0.72, 0.23)]
let radii: [CGFloat] = [0.085, 0.065, 0.075, 0.060, 0.070].map { $0 * content.width }

NSColor.white.setStroke()
for (i, satellite) in satellites.enumerated() {
    let edge = NSBezierPath()
    edge.move(to: hub)
    edge.line(to: satellite)
    edge.lineWidth = content.width * (i == 1 ? 0.045 : 0.028) // one heavy edge
    edge.lineCapStyle = .round
    edge.stroke()
}
let cross = NSBezierPath()
cross.move(to: satellites[0])
cross.line(to: satellites[1])
cross.lineWidth = content.width * 0.022
cross.lineCapStyle = .round
cross.stroke()

NSColor.white.setFill()
for (i, center) in ([hub] + satellites).enumerated() {
    let r = radii[i]
    NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)).fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
