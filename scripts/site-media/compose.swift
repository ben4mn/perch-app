// The image work for scripts/site-media.sh that ffmpeg alone does badly: eased crossfade frames between
// two stills, and a labelled contact sheet. Compiled once by the script; uses only the system's frameworks.
//
//   compose blend <jobs.tsv>          each line: a.png <TAB> b.png <TAB> weight 0...1 <TAB> out.png
//   compose sheet <rows.tsv> <out>    each line: label <TAB> picture <TAB> picture ...
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("can't read \(path)") }
    return image
}

func context(width: Int, height: Int) -> CGContext {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no context \(width)x\(height)") }
    context.interpolationQuality = .high
    return context
}

func save(_ context: CGContext, to path: String) {
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("can't write \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) { fail("can't write \(path)") }
}

/// b laid over a at `weight`: a at 0, b at 1. Both pictures are opaque and the same size.
func blend(_ jobs: [[String]]) {
    DispatchQueue.concurrentPerform(iterations: jobs.count) { index in
        let job = jobs[index]
        let a = load(job[0]), b = load(job[1])
        guard a.width == b.width, a.height == b.height else { fail("\(job[0]) and \(job[1]) differ in size") }
        let weight = CGFloat(Double(job[2]) ?? 0)
        let canvas = context(width: a.width, height: a.height)
        let rect = CGRect(x: 0, y: 0, width: a.width, height: a.height)
        canvas.draw(a, in: rect)
        canvas.setAlpha(min(max(weight, 0), 1))
        canvas.draw(b, in: rect)
        save(canvas, to: job[3])
    }
}

/// One row per scene: its id on the left, then its pictures scaled to one height.
func sheet(_ rows: [[String]], to path: String) {
    let cell = 560.0, gap = 16.0, labelWidth = 230.0, rowHeight = 330.0
    let columns = rows.map { $0.count - 1 }.max() ?? 0
    let width = Int(labelWidth + Double(columns) * (cell + gap) + gap)
    let height = Int(Double(rows.count) * (rowHeight + gap) + gap)
    let canvas = context(width: width, height: height)
    canvas.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
    canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
    for (row, entry) in rows.enumerated() {
        let top = Double(height) - gap - Double(row) * (rowHeight + gap)
        let label = NSAttributedString(string: entry[0], attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        label.draw(at: CGPoint(x: gap, y: top - rowHeight / 2 - 12))
        for (column, picture) in entry.dropFirst().enumerated() {
            let image = load(picture)
            let scale = min(cell / Double(image.width), rowHeight / Double(image.height))
            let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
            let x = labelWidth + Double(column) * (cell + gap)
            let rect = CGRect(x: x + (cell - size.width) / 2, y: top - rowHeight + (rowHeight - size.height) / 2, width: size.width, height: size.height)
            canvas.draw(image, in: rect)
            canvas.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
            canvas.stroke(rect, width: 1)
        }
    }
    NSGraphicsContext.current = nil
    save(canvas, to: path)
}

func rows(_ path: String) -> [[String]] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("can't read \(path)") }
    return text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "blend" where arguments.count == 3: blend(rows(arguments[2]))
case "sheet" where arguments.count == 4: sheet(rows(arguments[2]), to: arguments[3])
default: fail("usage: compose blend <jobs.tsv> | compose sheet <rows.tsv> <out.png>")
}
