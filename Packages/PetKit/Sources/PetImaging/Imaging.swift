import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PetCore
import UniformTypeIdentifiers

public enum ImagingError: Error, LocalizedError {
    case unreadable(String)
    case unwritable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let p): "cannot read image: \(p)"
        case .unwritable(let p): "cannot write image: \(p)"
        }
    }
}

public enum ImageFiles {
    public static func load(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw ImagingError.unreadable(url.path) }
        return img
    }

    /// Pixel size from the file header, without decoding the image.
    public static func pixelSize(_ url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImagingError.unwritable(url.path)
        }
        CGImageDestinationAddImage(dst, image, nil)
        guard CGImageDestinationFinalize(dst) else { throw ImagingError.unwritable(url.path) }
    }

    public static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw ImagingError.unwritable(url.path)
        }
        let fileProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(dst, fileProps)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
        for f in frames { CGImageDestinationAddImage(dst, f, frameProps) }
        guard CGImageDestinationFinalize(dst) else { throw ImagingError.unwritable(url.path) }
    }
}

public extension RGBAImage {
    /// Pixels as drawn by CoreGraphics (premultiplied RGBA8, top-left origin).
    init(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        pixels.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        self.init(width: w, height: h, pixels: pixels)
    }

    func makeCGImage() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func cropped(_ r: PixelRect) -> RGBAImage {
        var out = RGBAImage(width: r.width, height: r.height)
        for y in 0..<r.height {
            for x in 0..<r.width {
                let sx = r.x + x, sy = r.y + y
                guard sx >= 0, sy >= 0, sx < width, sy < height else { continue }
                out.set(x, y, pixel(sx, sy))
            }
        }
        return out
    }

    /// Draws `top` over self (same size, top-left aligned), source-over with premultiplied pixels.
    mutating func composite(_ top: RGBAImage) {
        for y in 0..<min(height, top.height) {
            for x in 0..<min(width, top.width) {
                let t = top.pixel(x, y)
                guard t.a > 0 else { continue }
                if t.a == 255 { set(x, y, t); continue }
                let b = pixel(x, y), k = 255 - Int(t.a)
                func mix(_ tc: UInt8, _ bc: UInt8) -> UInt8 { UInt8(min(255, Int(tc) + Int(bc) * k / 255)) }
                set(x, y, RGBA(r: mix(t.r, b.r), g: mix(t.g, b.g), b: mix(t.b, b.b), a: mix(t.a, b.a)))
            }
        }
    }

    /// Horizontally mirrored copy.
    func mirrored() -> RGBAImage {
        var out = RGBAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width { out.set(width - 1 - x, y, pixel(x, y)) }
        }
        return out
    }

    /// Nearest-neighbour resize by `factor` (keeps pixel art crisp), at least 1×1.
    func scaled(_ factor: Double) -> RGBAImage {
        let w = max(1, Int((Double(width) * factor).rounded())), h = max(1, Int((Double(height) * factor).rounded()))
        var out = RGBAImage(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w { out.set(x, y, pixel(min(width - 1, Int(Double(x) / factor)), min(height - 1, Int(Double(y) / factor)))) }
        }
        return out
    }

    /// Copies `src` into self at (x, y) (top-left origin).
    mutating func blit(_ src: RGBAImage, x: Int, y: Int) {
        for sy in 0..<src.height {
            for sx in 0..<src.width {
                let dx = x + sx, dy = y + sy
                guard dx >= 0, dy >= 0, dx < width, dy < height else { continue }
                set(dx, dy, src.pixel(sx, sy))
            }
        }
    }
}

/// Packs frames into a compact sheet (shelf packing) and produces atlas frames with pivots.
public enum SheetPacker {
    public struct Item {
        public var name: String
        public var image: RGBAImage
        /// Frame-relative, top-left origin.
        public var pivot: [Int]
        public init(name: String, image: RGBAImage, pivot: [Int]) {
            self.name = name
            self.image = image
            self.pivot = pivot
        }
    }

    public static func pack(_ items: [Item], padding: Int = 2, maxWidth: Int = 1024) -> (sheet: RGBAImage, frames: [String: AtlasFrame]) {
        let order = items.indices.sorted { (items[$0].image.height, items[$1].name) > (items[$1].image.height, items[$0].name) }
        var placements: [(Int, Int, Int)] = [] // item index, x, y
        var x = padding, y = padding, shelfHeight = 0, usedWidth = 0
        for i in order {
            let img = items[i].image
            if x + img.width + padding > maxWidth, x > padding {
                y += shelfHeight + padding
                x = padding
                shelfHeight = 0
            }
            placements.append((i, x, y))
            x += img.width + padding
            usedWidth = max(usedWidth, x)
            shelfHeight = max(shelfHeight, img.height)
        }
        var sheet = RGBAImage(width: max(usedWidth, 1), height: max(y + shelfHeight + padding, 1))
        var frames: [String: AtlasFrame] = [:]
        for (i, px, py) in placements {
            let item = items[i]
            sheet.blit(item.image, x: px, y: py)
            let p = item.pivot.count == 2 ? item.pivot : [item.image.width / 2, item.image.height]
            frames[item.name] = AtlasFrame(rect: CGRect(x: px, y: py, width: item.image.width, height: item.image.height),
                                           pivot: CGPoint(x: p[0], y: p[1]))
        }
        return (sheet, frames)
    }
}

/// Crops atlas frames out of a sheet.
public enum FrameCutter {
    public static func cut(atlas: SpriteAtlas, image: CGImage) -> [String: (image: CGImage, frame: ResolvedFrame)] {
        var out: [String: (CGImage, ResolvedFrame)] = [:]
        for (name, f) in atlas.resolvedFrames(imageWidth: image.width, imageHeight: image.height) {
            if let sub = image.cropping(to: f.rect.integral) { out[name] = (sub, f) }
        }
        return out
    }
}

/// A labelled grid of candidate frames, for picking indices into `labels.json`.
public enum ContactSheet {
    public static func render(source: RGBAImage, frames: [SlicedFrame], zoom: Int = 2, columns: Int = 10) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        let maxW = frames.map(\.rect.width).max()! * zoom, maxH = frames.map(\.rect.height).max()! * zoom
        let cellW = max(maxW, 40) + 12, cellH = maxH + 30
        let cols = min(columns, frames.count), rows = (frames.count + cols - 1) / cols
        let w = cols * cellW, h = rows * cellH
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 13, nil)

        for (n, f) in frames.enumerated() {
            let col = n % cols, row = n / cols
            // CG origin is bottom-left; row 0 is drawn at the top.
            let cellX = col * cellW, cellY = h - (row + 1) * cellH
            ctx.setFillColor(CGColor(gray: (row + col) % 2 == 0 ? 0.78 : 0.72, alpha: 1))
            ctx.fill(CGRect(x: cellX, y: cellY, width: cellW, height: cellH))
            if let img = source.cropped(f.rect).makeCGImage() {
                let dw = f.rect.width * zoom, dh = f.rect.height * zoom
                let dx = cellX + (cellW - dw) / 2, dy = cellY + 24
                ctx.draw(img, in: CGRect(x: dx, y: dy, width: dw, height: dh))
                // Pivot marker.
                ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0.6, alpha: 1))
                ctx.fill(CGRect(x: dx + f.pivot[0] * zoom - 2, y: dy + (f.rect.height - f.pivot[1]) * zoom - 1, width: 4, height: 2))
            }
            let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0.05, alpha: 1)] as CFDictionary
            let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, "\(f.index)" as CFString, attrs))
            ctx.textPosition = CGPoint(x: cellX + 4, y: cellY + 6)
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage()
    }
}
