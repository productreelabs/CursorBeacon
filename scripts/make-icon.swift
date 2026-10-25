// Draws the CursorBeacon app icon into an .iconset folder for iconutil.
// Usage: swiftc scripts/make-icon.swift -o make-icon && ./make-icon <output.iconset>

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// Draws the icon on a 1024-point canvas, y pointing down.
func drawIcon(in context: CGContext) {
    // Rounded square background, following the macOS icon grid.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let colors = [CGColor(srgbRed: 0.16, green: 0.22, blue: 0.52, alpha: 1), CGColor(srgbRed: 0.07, green: 0.09, blue: 0.24, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    context.restoreGState()

    let yellow = CGColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
    let tip = CGPoint(x: 360, y: 300)

    // Click rings around the arrow tip.
    for (radius, alpha) in [(150.0, 0.35), (95.0, 0.7)] {
        context.setStrokeColor(yellow.copy(alpha: alpha)!)
        context.setLineWidth(22)
        context.strokeEllipse(in: CGRect(x: tip.x - radius, y: tip.y - radius, width: radius * 2, height: radius * 2))
    }

    // The same arrow CursorBeacon draws, tip on the rings' center.
    let size: CGFloat = 520
    let points: [(CGFloat, CGFloat)] = [
        (0, 0), (0, 0.85), (0.22, 0.66), (0.36, 0.98), (0.50, 0.92), (0.36, 0.60), (0.62, 0.60)
    ]
    let arrow = CGMutablePath()
    arrow.addLines(between: points.map { CGPoint(x: tip.x + $0.0 * size, y: tip.y + $0.1 * size) })
    arrow.closeSubpath()
    context.addPath(arrow)
    context.setStrokeColor(.black)
    context.setLineWidth(36)
    context.setLineJoin(.round)
    context.strokePath()
    context.addPath(arrow)
    context.setFillColor(yellow)
    context.fillPath()
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let factor = CGFloat(pixels) / 1024
        context.scaleBy(x: factor, y: -factor)
        context.translateBy(x: 0, y: -1024)
        drawIcon(in: context)

        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        try png.write(to: output.appendingPathComponent(name))
    }
}
