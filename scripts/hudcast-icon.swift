// Turns TheHud's full-bleed iOS icon into a macOS .iconset: the artwork cut to the Mac's
// rounded square (824 of 1024, with the system's margin and drop shadow), at every size
// iconutil wants. Usage: swift scripts/hudcast-icon.swift <AppIcon.png> <out.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let art = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("usage: hudcast-icon <AppIcon.png> <out.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // Apple's grid: a 824pt squircle centred in 1024, its body a little above centre to leave
    // room for the shadow.
    let unit = size / 1024
    let body = CGRect(x: 100 * unit, y: 112 * unit, width: 824 * unit, height: 824 * unit)
    let shape = CGPath(roundedRect: body, cornerWidth: 185 * unit, cornerHeight: 185 * unit,
                       transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit,
                  color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(art, in: body)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(points * scale).write(to: out.appendingPathComponent(name))
    }
}
