// Draws Perch's app icons with Core Graphics: swift Design/render-icon.swift <out-dir> [palette]
// The idea: a "P" monogram on a softly lit tile. The hole in the letter is the Mac's notch,
// with one status light, because that is where Perch lives.
// The drawing never changes; a palette sets its colours. dusk is the default and the installed icon,
// slate and clay are the other muted ones, and ember is the original orange-to-rose icon, kept so it
// can be rebuilt.
// Afterwards, copy the results into the asset catalogs: Design/install-icons.sh <out-dir>
import AppKit

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ stops: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops)!
}

/// Every colour in the icon.
struct Palette {
    let tile: [CGColor]     // the tile's gradient: top left, middle, bottom right
    let glow: CGColor       // the soft light at the top left, fading to clear
    let letter: CGColor
    let letterShadow: CGColor
    let hole: CGColor       // the notch
    let light: CGColor      // its one status light
    var rim = c(0xFFFFFF, 0.18)         // the fine top stroke on the Mac tile
    var dropShadow = c(0x000000, 0.38)  // the Mac tile's shadow
}

let palettes: KeyValuePairs<String, Palette> = [
    // A deep ink tile. The status light is the one warm note left.
    "slate": Palette(tile: [c(0x3D3E49), c(0x2D2E37), c(0x23242B)], glow: c(0xFFFFFF, 0.10),
                     letter: c(0xF4EFE6), letterShadow: c(0x000000, 0.35), hole: c(0x0E0E12), light: c(0xE0A070)),
    // A quiet terracotta.
    "clay": Palette(tile: [c(0xC99A82), c(0xAD8171), c(0x8A5F66)], glow: c(0xFFF1DC, 0.25),
                    letter: c(0xFBF6EE), letterShadow: c(0x3A1E24, 0.40), hole: c(0x2A1E22), light: c(0xF0C09A)),
    // A grey violet that keeps a hint of the old rose.
    "dusk": Palette(tile: [c(0x6B6577), c(0x55506A), c(0x3F3B52)], glow: c(0xFFFFFF, 0.12),
                    letter: c(0xF6F1EA), letterShadow: c(0x0C0A14, 0.40), hole: c(0x17151D), light: c(0xE8B58A)),
    // The original: warm orange at the top left, deepening to rose at the bottom right.
    "ember": Palette(tile: [c(0xFF8A3D), c(0xF0503C), c(0xC02E5E)], glow: c(0xFFE2A8, 0.45),
                     letter: c(0xFFFBF5), letterShadow: c(0x5A0F2A, 0.45), hole: c(0x1A0F1E), light: c(0xFFB36B)),
]

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("Usage: swift Design/render-icon.swift <out-dir> [palette]\n".data(using: .utf8)!)
    exit(2)
}
let paletteName = args.count > 2 ? args[2] : "dusk"
guard let palette = palettes.first(where: { $0.key == paletteName })?.value else {
    let names = palettes.map(\.key).joined(separator: ", ")
    FileHandle.standardError.write("Unknown palette \"\(paletteName)\". Choose one of: \(names)\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// Draws the scene into a square `r`, coordinates scaled from a 1000-unit design grid (origin bottom left).
func scene(_ ctx: CGContext, _ r: CGRect, _ pal: Palette) {
    let k = r.width / 1000
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: r.minX + x * k, y: r.minY + y * k, width: w * k, height: h * k) }

    // The tile: a diagonal gradient from the top left to the bottom right, with a soft light.
    ctx.drawLinearGradient(gradient(pal.tile, [0, 0.55, 1]), start: p(150, 1000), end: p(850, 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.drawRadialGradient(gradient([pal.glow, pal.glow.copy(alpha: 0)!], [0, 1]),
                           startCenter: p(300, 820), startRadius: 0, endCenter: p(300, 820), endRadius: 620 * k, options: [])

    // The letter: one outline, so the stem and bowl meet in a single clean corner.
    let letter = CGMutablePath()
    letter.move(to: p(290, 262))
    letter.addLine(to: p(290, 690))
    letter.addArc(tangent1End: p(290, 808), tangent2End: p(408, 808), radius: 118 * k)
    letter.addLine(to: p(548, 808))
    letter.addArc(center: p(548, 618), radius: 190 * k, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
    letter.addLine(to: p(440, 428))
    letter.addLine(to: p(440, 262))
    letter.addArc(center: p(365, 262), radius: 75 * k, startAngle: 0, endAngle: .pi, clockwise: true)
    letter.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 36 * k, color: pal.letterShadow)
    ctx.addPath(letter)
    ctx.setFillColor(pal.letter)
    ctx.fillPath()
    ctx.restoreGState()

    // The notch, as the hole in the letter, with one status light.
    ctx.addPath(CGPath(roundedRect: rect(432, 560, 196, 116), cornerWidth: 58 * k, cornerHeight: 58 * k, transform: nil))
    ctx.setFillColor(pal.hole)
    ctx.fillPath()
    ctx.setFillColor(pal.light)
    ctx.fillEllipse(in: rect(463, 601, 34, 34))
}

func render(size: Int, name: String, opaque: Bool = false, draw: (CGContext, CGRect) -> Void) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx, CGRect(x: 0, y: 0, width: size, height: size))
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

/// macOS's icon shape: a continuous-corner rounded square.
func squircle(_ r: CGRect) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: r.width * 0.225, cornerHeight: r.width * 0.225, transform: nil)
}

// iPhone: full bleed and opaque; iOS applies its own mask.
render(size: 1024, name: "icon-ios.png", opaque: true) { ctx, rect in scene(ctx, rect, palette) }

// Mac: the standard 824-point tile in a 1024 canvas, with a shadow and a fine top highlight.
// The tile's base takes the gradient's last colour, so nothing else shows at the edge.
render(size: 1024, name: "icon-mac.png") { ctx, rect in
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(tile)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: palette.dropShadow)
    ctx.addPath(shape)
    ctx.setFillColor(palette.tile.last!)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    scene(ctx, tile, palette)
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(palette.rim)
    ctx.setLineWidth(2)
    ctx.strokePath()
}

// The scene alone, for the welcome screen and docs.
render(size: 512, name: "mark.png") { ctx, rect in
    ctx.addPath(squircle(rect.insetBy(dx: 6, dy: 6)))
    ctx.clip()
    scene(ctx, rect, palette)
}
print("Wrote the \(paletteName) icons to \(out.path)")
