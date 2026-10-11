import CoreGraphics
import Foundation

/// `sprites/atlas.json`: named frames with variable rects and a pivot.
///
/// Rects and pivots are in image pixels with a **top-left** origin (as image editors show them).
/// The pivot is the ground-contact point inside the frame; frames are aligned on it.
public struct SpriteAtlas: Codable, Sendable {
    public var formatVersion: Int?
    public var image: String
    /// The direction sprites face natively. The renderer mirrors for the other direction.
    public var facing: Facing
    public var frames: [String: AtlasFrame]
    /// Optional uniform grid (Shimeji / itch packs). Frames are named "0", "1", … unless `names` is given.
    public var grid: GridSpec?

    public init(image: String, facing: Facing = .right, frames: [String: AtlasFrame], grid: GridSpec? = nil) {
        self.formatVersion = supportedFormatVersion
        self.image = image
        self.facing = facing
        self.frames = frames
        self.grid = grid
    }

    enum CodingKeys: String, CodingKey { case formatVersion, image, facing, frames, grid }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion)
        image = try c.decode(.image, default: "sheet.png")
        facing = try c.decode(.facing, default: .right)
        frames = try c.decode(.frames, default: [:])
        grid = try c.decodeIfPresent(GridSpec.self, forKey: .grid)
    }

    /// All frames (explicit + grid-generated) once the image size is known. Explicit frames win.
    public func resolvedFrames(imageWidth: Int, imageHeight: Int) -> [String: ResolvedFrame] {
        var out: [String: ResolvedFrame] = [:]
        if let grid, grid.frameSize.count == 2, grid.frameSize[0] > 0, grid.frameSize[1] > 0 {
            let w = grid.frameSize[0], h = grid.frameSize[1]
            let cols = Int(Double(imageWidth) / w), rows = Int(Double(imageHeight) / h)
            var index = 0
            for row in 0..<max(rows, 0) {
                for col in 0..<max(cols, 0) {
                    let name = grid.names.flatMap { index < $0.count ? $0[index] : nil } ?? String(index)
                    let pivot = grid.pivot.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
                        ?? CGPoint(x: w / 2, y: h)
                    out[name] = ResolvedFrame(rect: CGRect(x: Double(col) * w, y: Double(row) * h, width: w, height: h), pivot: pivot)
                    index += 1
                }
            }
        }
        for (name, frame) in frames {
            if let resolved = frame.resolved { out[name] = resolved }
        }
        return out
    }
}

public struct AtlasFrame: Codable, Sendable, Hashable {
    /// [x, y, width, height]
    public var rect: [Double]
    /// [x, y] inside the frame. Defaults to bottom-centre.
    public var pivot: [Double]?

    public init(rect: CGRect, pivot: CGPoint) {
        self.rect = [rect.minX, rect.minY, rect.width, rect.height].map(Double.init)
        self.pivot = [pivot.x, pivot.y].map(Double.init)
    }

    public var resolved: ResolvedFrame? {
        guard rect.count == 4, rect[2] > 0, rect[3] > 0 else { return nil }
        let r = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
        let p = pivot.flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } ?? CGPoint(x: r.width / 2, y: r.height)
        return ResolvedFrame(rect: r, pivot: p)
    }
}

public struct GridSpec: Codable, Sendable, Hashable {
    public var frameSize: [Double]
    public var pivot: [Double]?
    public var names: [String]?
}

/// A frame with validated geometry. `rect` in image px (top-left origin); `pivot` in frame px (top-left origin).
public struct ResolvedFrame: Sendable, Hashable {
    public var rect: CGRect
    public var pivot: CGPoint

    public init(rect: CGRect, pivot: CGPoint) {
        self.rect = rect
        self.pivot = pivot
    }

    /// Extents of the frame around its pivot, in frame px (y up).
    public var extents: SpriteExtents {
        SpriteExtents(left: pivot.x, right: rect.width - pivot.x, up: pivot.y, down: rect.height - pivot.y)
    }
}

/// Distances from the pivot to each side of a sprite. y is up: `up` is above the pivot.
public struct SpriteExtents: Sendable, Hashable {
    public var left: Double
    public var right: Double
    public var up: Double
    public var down: Double

    public init(left: Double, right: Double, up: Double, down: Double) {
        self.left = left
        self.right = right
        self.up = up
        self.down = down
    }

    public static let zero = SpriteExtents(left: 0, right: 0, up: 0, down: 0)

    public func union(_ o: SpriteExtents) -> SpriteExtents {
        SpriteExtents(left: max(left, o.left), right: max(right, o.right), up: max(up, o.up), down: max(down, o.down))
    }

    public func scaled(_ s: Double) -> SpriteExtents {
        SpriteExtents(left: left * s, right: right * s, up: up * s, down: down * s)
    }

    /// Extents valid for both facings (mirroring swaps left and right).
    public var mirrorSafe: SpriteExtents {
        let h = max(left, right)
        return SpriteExtents(left: h, right: h, up: up, down: down)
    }
}
