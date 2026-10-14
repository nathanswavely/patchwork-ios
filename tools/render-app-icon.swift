import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: String) -> CGColor {
    let v = Int(hex.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
typealias Piece = ([(Double, Double)], String)
func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [(Double, Double)] { [(x, y), (x + w, y), (x + w, y + h), (x, y + h)] }

let primary = "#C02624", secondary = "#D89E13", ground = "#261922"
let t = 0.25
let sawtooth: [Piece] = [
    (rect(0, 0, 1, 1), ground), (rect(t, t, 2 * t, 2 * t), primary),
    ([(t, 0), (2 * t, t), (3 * t, 0)], secondary), ([(t, 1), (2 * t, 3 * t), (3 * t, 1)], secondary),
    ([(0, t), (t, 2 * t), (0, 3 * t)], secondary), ([(1, t), (3 * t, 2 * t), (1, 3 * t)], secondary),
    (rect(0, 0, t, t), secondary), (rect(3 * t, 0, t, t), secondary), (rect(0, 3 * t, t, t), secondary), (rect(3 * t, 3 * t, t, t), secondary),
]
let h = 0.5
let pinwheel: [Piece] = [
    ([(0, 0), (h, 0), (h, h)], primary), ([(h, 0), (1, 0), (h, h)], ground),
    ([(1, 0), (1, h), (h, h)], secondary), ([(1, h), (1, 1), (h, h)], ground),
    ([(1, 1), (h, 1), (h, h)], primary), ([(h, 1), (0, 1), (h, h)], ground),
    ([(0, 1), (0, h), (h, h)], secondary), ([(0, h), (0, 0), (h, h)], ground),
]
// Four blocks as one small quilt: the thing the app is named for.
func quarter(_ pieces: [Piece], _ ox: Double, _ oy: Double) -> [Piece] { pieces.map { ($0.0.map { (ox + $0.0 / 2, oy + $0.1 / 2) }, $0.1) } }
let swapped = pinwheel.map { ($0.0, $0.1 == primary ? secondary : ($0.1 == secondary ? primary : $0.1)) }
let quilt: [Piece] = quarter(sawtooth, 0, 0) + quarter(pinwheel, 0.5, 0) + quarter(swapped, 0, 0.5) + quarter(sawtooth, 0.5, 0.5)

func render(_ pieces: [Piece], inset: Double, seam: Bool, to path: String) {
    let side = 1024
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(color(ground)); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let s = Double(side) * (1 - 2 * inset), o = Double(side) * inset
    ctx.translateBy(x: 0, y: CGFloat(side)); ctx.scaleBy(x: 1, y: -1)
    for (points, hex) in pieces {
        ctx.beginPath()
        for (i, p) in points.enumerated() {
            let q = CGPoint(x: o + p.0 * s, y: o + p.1 * s)
            i == 0 ? ctx.move(to: q) : ctx.addLine(to: q)
        }
        ctx.closePath(); ctx.setFillColor(color(hex)); ctx.fillPath()
    }
    if seam {
        ctx.setStrokeColor(color(ground)); ctx.setLineWidth(10)
        ctx.stroke(CGRect(x: o, y: o, width: s, height: s))
        ctx.move(to: CGPoint(x: o + s / 2, y: o)); ctx.addLine(to: CGPoint(x: o + s / 2, y: o + s))
        ctx.move(to: CGPoint(x: o, y: o + s / 2)); ctx.addLine(to: CGPoint(x: o + s, y: o + s / 2)); ctx.strokePath()
    }
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
}
let dir = CommandLine.arguments[1]
render(sawtooth, inset: 0, seam: false, to: dir + "/a-sawtooth.png")
render(sawtooth, inset: 0.14, seam: false, to: dir + "/b-sawtooth-inset.png")
render(quilt, inset: 0.1, seam: true, to: dir + "/c-four-block-quilt.png")
