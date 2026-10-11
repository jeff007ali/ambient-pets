import Foundation

/// An RGBA8 bitmap, row-major, top-left origin. Only the alpha channel matters for slicing.
public struct RGBAImage: Sendable, Hashable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
    }

    public func pixel(_ x: Int, _ y: Int) -> RGBA {
        let i = (y * width + x) * 4
        return RGBA(r: pixels[i], g: pixels[i + 1], b: pixels[i + 2], a: pixels[i + 3])
    }

    public mutating func set(_ x: Int, _ y: Int, _ c: RGBA) {
        let i = (y * width + x) * 4
        pixels[i] = c.r; pixels[i + 1] = c.g; pixels[i + 2] = c.b; pixels[i + 3] = c.a
    }

    public func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
}

public struct RGBA: Sendable, Hashable {
    public var r, g, b, a: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// `#RRGGBB` or `RRGGBB`.
    public init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: UInt8(v >> 16 & 0xFF), g: UInt8(v >> 8 & 0xFF), b: UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    func close(to o: RGBA, tolerance: Int) -> Bool {
        abs(Int(r) - Int(o.r)) <= tolerance && abs(Int(g) - Int(o.g)) <= tolerance && abs(Int(b) - Int(o.b)) <= tolerance
    }
}

/// Integer pixel rect, top-left origin, `maxX`/`maxY` exclusive.
public struct PixelRect: Sendable, Hashable, Codable {
    public var x, y, width, height: Int
    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Int { x + width }
    public var maxY: Int { y + height }

    public func union(_ o: PixelRect) -> PixelRect {
        let nx = min(x, o.x), ny = min(y, o.y)
        return PixelRect(x: nx, y: ny, width: max(maxX, o.maxX) - nx, height: max(maxY, o.maxY) - ny)
    }

    /// Chebyshev gap between two rects (0 if they touch or overlap).
    public func gap(to o: PixelRect) -> Int {
        max(max(o.x - maxX, x - o.maxX, 0), max(o.y - maxY, y - o.maxY, 0))
    }
}

public struct SlicedFrame: Sendable, Hashable, Codable {
    public var index: Int
    /// In the source sheet.
    public var rect: PixelRect
    /// Frame-relative, top-left origin: bottom-centre of the opaque pixels (the feet).
    public var pivot: [Int]
    public var pixelCount: Int
}

/// Auto-slicing of irregular sprite sheets (plan §5 M2): key out the background, find connected components,
/// merge nearby pieces (detached effects, gaps), and order frames for labelling.
public enum SpriteSlicer {
    public struct Options: Sendable {
        /// nil = take the top-left pixel as the background colour (if it's opaque).
        public var background: RGBA?
        public var tolerance = 8
        /// Components closer than this (px) are merged into one frame.
        public var mergeDistance = 3
        /// Frames with fewer opaque pixels are dropped as noise.
        public var minPixels = 16
        public init(background: RGBA? = nil) { self.background = background }
    }

    /// Detected background colour: the top-left pixel, unless it's already transparent.
    public static func detectBackground(_ img: RGBAImage) -> RGBA? {
        guard img.width > 0, img.height > 0 else { return nil }
        let c = img.pixel(0, 0)
        return c.a == 0 ? nil : RGBA(r: c.r, g: c.g, b: c.b)
    }

    /// Turns every pixel close to `color` fully transparent.
    public static func keyOut(_ img: inout RGBAImage, color: RGBA, tolerance: Int) {
        for y in 0..<img.height {
            for x in 0..<img.width where img.pixel(x, y).close(to: color, tolerance: tolerance) {
                img.set(x, y, RGBA(r: 0, g: 0, b: 0, a: 0))
            }
        }
    }

    /// 8-connected components of non-transparent pixels: bounding rect + pixel count.
    public static func components(_ img: RGBAImage) -> [(rect: PixelRect, pixels: Int)] {
        let w = img.width, h = img.height
        var visited = [Bool](repeating: false, count: w * h)
        var out: [(PixelRect, Int)] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where !visited[start] && img.pixels[start * 4 + 3] > 0 {
            var minX = w, minY = h, maxX = -1, maxY = -1, count = 0
            visited[start] = true
            stack.append(start)
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                count += 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let j = ny * w + nx
                        if !visited[j] && img.pixels[j * 4 + 3] > 0 {
                            visited[j] = true
                            stack.append(j)
                        }
                    }
                }
            }
            out.append((PixelRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1), count))
        }
        return out
    }

    /// Merges boxes whose gap is ≤ `distance`, repeatedly, until stable.
    public static func merge(_ boxes: [(rect: PixelRect, pixels: Int)], distance: Int) -> [(rect: PixelRect, pixels: Int)] {
        var items = boxes
        var changed = true
        while changed {
            changed = false
            var i = 0
            while i < items.count {
                var j = i + 1
                while j < items.count {
                    if items[i].rect.gap(to: items[j].rect) <= distance {
                        items[i] = (items[i].rect.union(items[j].rect), items[i].pixels + items[j].pixels)
                        items.remove(at: j)
                        changed = true
                    } else {
                        j += 1
                    }
                }
                i += 1
            }
        }
        return items
    }

    /// Reading order: rows top to bottom (a box joins the current row if it starts above the row's bottom), then left to right.
    public static func readingOrder(_ rects: [PixelRect]) -> [PixelRect] {
        let sorted = rects.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        var rows: [[PixelRect]] = []
        var rowBottom = Int.min
        for r in sorted {
            if rows.isEmpty || r.y >= rowBottom {
                rows.append([r])
                rowBottom = r.maxY
            } else {
                rows[rows.count - 1].append(r)
                rowBottom = max(rowBottom, r.maxY)
            }
        }
        return rows.flatMap { $0.sorted { $0.x < $1.x } }
    }

    /// Bottom-centre of the opaque pixels: lowest opaque row, mean x of opaque pixels in the bottom 6 rows.
    public static func autoPivot(_ img: RGBAImage, in rect: PixelRect) -> [Int] {
        var bottom = -1
        for y in stride(from: rect.maxY - 1, through: rect.y, by: -1) {
            if (rect.x..<rect.maxX).contains(where: { img.alpha($0, y) > 0 }) { bottom = y; break }
        }
        guard bottom >= 0 else { return [rect.width / 2, rect.height] }
        var sum = 0, n = 0
        for y in max(rect.y, bottom - 5)...bottom {
            for x in rect.x..<rect.maxX where img.alpha(x, y) > 0 {
                sum += x; n += 1
            }
        }
        let cx = n > 0 ? sum / n : rect.x + rect.width / 2
        return [cx - rect.x, bottom - rect.y + 1]
    }

    /// Feet height, but x from the centre of the chest band (20–55 % from the top). Steadier than the feet for
    /// walk cycles and poses with a raised knee, where the feet move but the body shouldn't.
    public static func torsoPivot(_ img: RGBAImage, in rect: PixelRect) -> [Int] {
        let feet = autoPivot(img, in: rect)
        var sum = 0, n = 0
        for y in (rect.y + rect.height * 20 / 100)..<max(rect.y + rect.height * 55 / 100, rect.y + 1) {
            for x in rect.x..<rect.maxX where img.alpha(x, y) > 0 {
                sum += x; n += 1
            }
        }
        return n > 0 ? [sum / n - rect.x, feet[1]] : feet
    }

    /// Full pipeline. `img` is keyed in place so the caller can crop transparent frames from it.
    public static func slice(_ img: inout RGBAImage, options: Options = Options()) -> (background: RGBA?, frames: [SlicedFrame]) {
        let bg = options.background ?? detectBackground(img)
        if let bg { keyOut(&img, color: bg, tolerance: options.tolerance) }
        let merged = merge(components(img), distance: options.mergeDistance).filter { $0.pixels >= options.minPixels }
        let counts = Dictionary(merged.map { ($0.rect, $0.pixels) }, uniquingKeysWith: +)
        let ordered = readingOrder(merged.map(\.rect))
        let frames = ordered.enumerated().map { i, r in
            SlicedFrame(index: i, rect: r, pivot: autoPivot(img, in: r), pixelCount: counts[r] ?? 0)
        }
        return (bg, frames)
    }
}
