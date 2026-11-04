import AppKit

// Dessine l'icône de l'app : fond dégradé arrondi + glyphe presse-papiers.
func drawIcon(size: CGFloat) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.08
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.98, alpha: 1.0),
        NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.80, alpha: 1.0)
    ])
    gradient?.draw(in: path, angle: -90)

    // Trois feuillets décalés, évoquant l'historique multiple.
    let sheetW = rect.width * 0.46
    let sheetH = rect.height * 0.56
    let offsets: [(CGFloat, CGFloat, CGFloat)] = [(-0.10, 0.10, 0.35), (-0.03, 0.03, 0.6), (0.05, -0.05, 1.0)]
    for (dx, dy, alpha) in offsets {
        let r = NSRect(x: rect.midX - sheetW / 2 + rect.width * dx,
                       y: rect.midY - sheetH / 2 + rect.height * dy,
                       width: sheetW, height: sheetH)
        let p = NSBezierPath(roundedRect: r, xRadius: r.width * 0.12, yRadius: r.width * 0.12)
        NSColor.white.withAlphaComponent(alpha).setFill()
        p.fill()
    }

    // Lignes de texte sur le feuillet de devant
    let front = NSRect(x: rect.midX - sheetW / 2 + rect.width * 0.05,
                       y: rect.midY - sheetH / 2 - rect.height * 0.05,
                       width: sheetW, height: sheetH)
    NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.82, alpha: 0.85).setFill()
    for i in 0..<3 {
        let lh = front.height * 0.085
        let w = front.width * (i == 2 ? 0.44 : 0.66)
        let y = front.maxY - front.height * (0.26 + CGFloat(i) * 0.20)
        NSBezierPath(roundedRect: NSRect(x: front.minX + front.width * 0.17, y: y, width: w, height: lh),
                     xRadius: lh / 2, yRadius: lh / 2).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments[1]
for px in [16, 32, 64, 128, 256, 512, 1024] {
    guard let rep = drawIcon(size: CGFloat(px)),
          let data = rep.representation(using: .png, properties: [:]) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(px).png"))
}
print("icônes générées")
