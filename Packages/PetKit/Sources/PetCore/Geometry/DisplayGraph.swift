import CoreGraphics
import Foundation

/// How connected displays touch each other (plan §4.3), from their AppKit frames.
public struct DisplayGraph: Sendable {
    public enum Direction: String, Sendable, CaseIterable { case left, right, above, below }

    public struct Link: Sendable, Hashable {
        public var from: UInt32
        public var to: UInt32
        public var direction: Direction
        /// Length of the shared edge, points.
        public var overlap: Double
    }

    public let displays: [DisplayGeometry]
    public let links: [Link]

    /// Edges closer than `tolerance` count as touching; the shared stretch must be at least `minOverlap` long.
    public init(_ displays: [DisplayGeometry], tolerance: Double = 2, minOverlap: Double = 80) {
        self.displays = displays
        var links: [Link] = []
        for a in displays {
            for b in displays where a.id != b.id {
                let fa = a.frame, fb = b.frame
                let yOverlap = min(fa.maxY, fb.maxY) - max(fa.minY, fb.minY)
                let xOverlap = min(fa.maxX, fb.maxX) - max(fa.minX, fb.minX)
                if abs(fa.maxX - fb.minX) <= tolerance, yOverlap >= minOverlap { links.append(Link(from: a.id, to: b.id, direction: .right, overlap: yOverlap)) }
                if abs(fa.minX - fb.maxX) <= tolerance, yOverlap >= minOverlap { links.append(Link(from: a.id, to: b.id, direction: .left, overlap: yOverlap)) }
                if abs(fa.maxY - fb.minY) <= tolerance, xOverlap >= minOverlap { links.append(Link(from: a.id, to: b.id, direction: .above, overlap: xOverlap)) }
                if abs(fa.minY - fb.maxY) <= tolerance, xOverlap >= minOverlap { links.append(Link(from: a.id, to: b.id, direction: .below, overlap: xOverlap)) }
            }
        }
        self.links = links
    }

    public func neighbors(of id: UInt32) -> [Link] { links.filter { $0.from == id } }

    /// The display a flight from `id` heading `side` reaches next: the side neighbour if any, else the nearest other
    /// display in that direction (reached with a fade hop), else nil.
    public func next(from id: UInt32, heading side: HorizontalSide) -> (display: DisplayGeometry, continuous: Bool)? {
        guard let a = displays.first(where: { $0.id == id }) else { return nil }
        let dir: Direction = side == .right ? .right : .left
        if let l = neighbors(of: id).filter({ $0.direction == dir }).max(by: { $0.overlap < $1.overlap }),
           let b = displays.first(where: { $0.id == l.to }) {
            return (b, true)
        }
        let others = displays.filter { $0.id != id && (side == .right ? $0.frame.midX > a.frame.midX : $0.frame.midX < a.frame.midX) }
        return others.min(by: { abs($0.frame.midX - a.frame.midX) < abs($1.frame.midX - a.frame.midX) }).map { ($0, false) }
    }
}
