import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import HudCore

/// `hudshot --icons`: the app icon in every theme colour, made from the mustard icon by the same
/// OKLCH turn the app gives its accent, so icon and app always match. Writes the iPhone's
/// alternate icon sets and the Android launcher icons, and a sheet of them all into the out folder.
enum ThemeIcons {
    static func make(root: URL, sheet: URL) throws {
        let assets = root.appendingPathComponent("App/TheHud/Assets.xcassets")
        let master = try load(assets.appendingPathComponent("AppIcon.appiconset/AppIcon.png"))
        var tiles: [CGImage] = []
        for theme in ThemeColor.allCases {
            let icon = theme == .mustard ? master : shifted(master, theme)
            tiles.append(icon)
            guard let name = theme.iconName else { continue }
            let set = assets.appendingPathComponent("\(name).appiconset")
            try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
            try save(icon, to: set.appendingPathComponent("AppIcon.png"))
            try contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        }

        let res = root.appendingPathComponent("android/app/src/main/res")
        for density in ["mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"] {
            let dir = res.appendingPathComponent("mipmap-\(density)")
            for variant in ["ic_launcher", "ic_launcher_round"] {
                let base = try load(dir.appendingPathComponent("\(variant).png"))
                for theme in ThemeColor.allCases where theme != .mustard {
                    let file = variant.replacingOccurrences(of: "ic_launcher", with: "ic_launcher_\(theme.rawValue)")
                    try save(shifted(base, theme), to: dir.appendingPathComponent("\(file).png"))
                }
            }
        }

        try save(contactSheet(tiles), to: sheet)
        print("wrote \(ThemeColor.allCases.count - 1) alternate icons and \(sheet.lastPathComponent)")
    }

    private static let contents = """
    {
      "images" : [
        {
          "filename" : "AppIcon.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """

    private static func shifted(_ image: CGImage, _ theme: ThemeColor) -> CGImage {
        let w = image.width, h = image.height
        var pixels = [UInt32](repeating: 0, count: w * h)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Byte order 32 little with alpha first: each UInt32 reads as ARGB.
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        pixels.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: space, bitmapInfo: info)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var cache: [UInt32: UInt32] = [:]
        for i in pixels.indices {
            let p = pixels[i]
            let alpha = p >> 24
            guard alpha > 0 else { continue }
            if let done = cache[p] { pixels[i] = done; continue }
            // Un-premultiply, turn, premultiply again.
            func channel(_ shift: UInt32) -> UInt32 { min(255, ((p >> shift) & 0xFF) * 255 / alpha) }
            let straight = 0xFF00_0000 | channel(16) << 16 | channel(8) << 8 | channel(0)
            let t = theme.color(straight)
            func back(_ shift: UInt32) -> UInt32 { ((t >> shift) & 0xFF) * alpha / 255 }
            let out = alpha << 24 | back(16) << 16 | back(8) << 8 | back(0)
            cache[p] = out
            pixels[i] = out
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: space, bitmapInfo: info)!.makeImage()!
        }
    }

    private static func contactSheet(_ tiles: [CGImage]) -> CGImage {
        let size = 256, gap = 24
        let w = tiles.count * size + (tiles.count + 1) * gap, h = size + gap * 2
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        for (i, tile) in tiles.enumerated() {
            let rect = CGRect(x: gap + i * (size + gap), y: gap, width: size, height: size)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 56, cornerHeight: 56, transform: nil))
            ctx.clip()
            ctx.draw(tile, in: rect)
            ctx.restoreGState()
        }
        return ctx.makeImage()!
    }

    private static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Hudshot.Failure("cannot read \(url.path)")
        }
        return image
    }

    private static func save(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Hudshot.Failure("cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Hudshot.Failure("cannot write \(url.path)") }
    }
}
