// Run: swift Scripts/generate_icon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon.png
import AppKit

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let c = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: Double, _ g: Double, _ b: Double) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, 1])! }
let blue = CGGradient(colorsSpace: space, colors: [color(0.27, 0.53, 1), color(0.11, 0.31, 0.82)] as CFArray, locations: nil)!
c.drawLinearGradient(blue, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])
// An alarm clock at seven: a face, two hands, and cat ears for bells.
let center = CGPoint(x: 512, y: 478)
func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
c.setFillColor(color(1, 1, 1))
c.fillEllipse(in: CGRect(x: center.x - 272, y: center.y - 272, width: 544, height: 544))
// Each ear is a triangle rooted inside the face, its corners rounded by the stroke.
c.setLineCap(.round)
c.setLineJoin(.round)
c.setLineWidth(44)
c.setStrokeColor(color(1, 1, 1))
for side in [-1.0, 1.0] {
    func point(_ degrees: Double, _ radius: Double) -> CGPoint {
        CGPoint(x: center.x + side * radius * cos(radians(degrees)), y: center.y + radius * sin(radians(degrees)))
    }
    c.move(to: point(32, 232))
    c.addLine(to: point(53, 360))
    c.addLine(to: point(74, 232))
    c.closePath()
    c.drawPath(using: .fillStroke)
}
c.setLineWidth(54)
c.setStrokeColor(color(0.15, 0.39, 0.92))
c.move(to: CGPoint(x: center.x, y: center.y + 168))
c.addLine(to: center)
c.addLine(to: CGPoint(x: center.x + 122 * cos(radians(240)), y: center.y + 122 * sin(radians(240))))
c.strokePath()
let data = NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
try data.write(to: URL(filePath: CommandLine.arguments[1]))
