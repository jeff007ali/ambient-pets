import CoreGraphics
import Foundation

/// A connected display, in **AppKit global coordinates** (origin bottom-left of the primary display, y up).
public struct DisplayGeometry: Sendable, Hashable, Identifiable {
    /// `CGDirectDisplayID`.
    public var id: UInt32
    public var frame: CGRect
    /// Excludes the menu bar and the Dock.
    public var visibleFrame: CGRect
    public var backingScale: Double

    public init(id: UInt32, frame: CGRect, visibleFrame: CGRect, backingScale: Double) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScale = backingScale
    }
}

/// The one place that converts between AppKit and CG/AX/CGWindowList global coordinates.
///
/// - AppKit: origin at the bottom-left of the primary display, y grows **up**.
/// - CG (Quartz Display Services, CGWindowList, Accessibility): origin at the top-left of the primary display, y grows **down**.
///
/// Both spaces share x. The flip is about the primary display's height, for every display.
public enum CoordinateSpace {
    public static func appKitToCG(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    public static func cgToAppKit(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    public static func appKitToCG(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        let r = r.standardized
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    public static func cgToAppKit(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        let r = r.standardized
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Height of the primary display (the one whose AppKit frame starts at the origin).
    public static func primaryHeight(of displays: [DisplayGeometry]) -> CGFloat {
        (displays.first { $0.frame.origin == .zero } ?? displays.first)?.frame.height ?? 0
    }

    /// Rounds a point to the nearest device pixel for a given backing scale (avoids blurry sprites).
    public static func pixelAligned(_ p: CGPoint, scale: Double) -> CGPoint {
        let s = max(scale, 1)
        return CGPoint(x: (p.x * s).rounded() / s, y: (p.y * s).rounded() / s)
    }
}

/// Window geometry for one scene: a small window sized to the sprite plus effect padding.
///
/// Positions in scenes always refer to the **pivot** (the pet's feet). `pivot` is where that point sits inside the
/// window, in points with a bottom-left origin.
public struct PetBox: Sendable, Hashable {
    public var size: CGSize
    public var pivot: CGPoint
    /// Sprite extents around the pivot, in points (mirror-safe).
    public var sprite: SpriteExtents

    public init(size: CGSize, pivot: CGPoint, sprite: SpriteExtents) {
        self.size = size
        self.pivot = pivot
        self.sprite = sprite
    }

    public struct Padding: Sendable, Hashable {
        public var side: Double, top: Double, bottom: Double
        public init(side: Double, top: Double, bottom: Double) {
            self.side = side
            self.top = top
            self.bottom = bottom
        }
    }

    /// - Parameters:
    ///   - extents: union of all frame extents used by the scene, native px.
    ///   - scale: native px → points.
    ///   - padding: extra room for effects, in points.
    ///   - minWidth: e.g. to fit a speech bubble.
    public static func make(extents: SpriteExtents, scale: Double, padding: Padding, minWidth: Double = 0) -> PetBox {
        let e = extents.mirrorSafe.scaled(scale)
        var side = padding.side
        let contentWidth = e.left + e.right + 2 * side
        if contentWidth < minWidth { side += (minWidth - contentWidth) / 2 }
        let pivot = CGPoint(x: (side + e.left).rounded(.up), y: (padding.bottom + e.down).rounded(.up))
        let size = CGSize(width: (pivot.x + e.right + side).rounded(.up), height: (pivot.y + e.up + padding.top).rounded(.up))
        return PetBox(size: size, pivot: pivot, sprite: e)
    }

    /// Window frame (AppKit global) that puts the pivot at `position`.
    public func windowFrame(pivotAt position: CGPoint) -> CGRect {
        CGRect(origin: CGPoint(x: position.x - pivot.x, y: position.y - pivot.y), size: size)
    }
}
