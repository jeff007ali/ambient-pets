import AppKit
import PetCore
import QuartzCore

/// A small rounded speech bubble above the pet's head, in its own click-through window (so it's never cut off by
/// the pet's window), always fully on screen. It follows the pet; the director keeps the pet still long enough to
/// read it (`readingTime`), and removes it when the pet leaves.
@MainActor
final class SpeechBubble {
    static let maxTextWidth: CGFloat = 180
    static let padding = CGSize(width: 10, height: 6)
    static let tail: CGFloat = 7
    /// Room around the bubble for its shadow and tail.
    static let margin: CGFloat = 6
    static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)

    /// Bubbles still on screen (they keep themselves alive until they fade out).
    private static var live: [ObjectIdentifier: SpeechBubble] = [:]

    private let window: PetWindowController
    private let shape = CAShapeLayer()
    private let label = CATextLayer()
    private let size: CGSize
    private let textSize: CGSize
    private let display: DisplayGeometry
    private var tailX: CGFloat?
    private var fadeTimer: Timer?
    private var closeTimer: Timer?
    private(set) var isClosed = false

    /// Reading time: 2.8 s plus ~70 ms per character, 2.8–6 s.
    static func readingTime(_ text: String) -> Double { min(max(2.8, 1.4 + 0.07 * Double(text.count)), 6) }

    /// - Parameters:
    ///   - head: the point just above the pet's head, global coordinates.
    init(text: String, head: CGPoint, display: DisplayGeometry) {
        self.display = display
        let attributed = NSAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: NSColor.black])
        textSize = attributed.boundingRect(with: CGSize(width: Self.maxTextWidth, height: 300),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading]).integral.size
        size = CGSize(width: textSize.width + Self.padding.width * 2, height: textSize.height + Self.padding.height * 2)
        let m = Self.margin
        window = PetWindowController(size: CGSize(width: size.width + 2 * m, height: size.height + Self.tail + 2 * m))

        shape.fillColor = NSColor(white: 1, alpha: 0.98).cgColor
        shape.strokeColor = NSColor(white: 0.15, alpha: 0.9).cgColor
        shape.lineWidth = 1
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowOpacity = 0.3
        shape.shadowRadius = 2.5
        shape.shadowOffset = CGSize(width: 0, height: -1)
        label.string = attributed
        label.isWrapped = true
        label.alignmentMode = .center
        label.frame = CGRect(x: m + Self.padding.width, y: m + Self.tail + Self.padding.height - 1,
                             width: textSize.width, height: textSize.height)
        for l in [shape, label] as [CALayer] { l.actions = noImplicitActions().merging(["path": NSNull()]) { a, _ in a } }
        window.rootLayer.addSublayer(shape)
        window.rootLayer.addSublayer(label)
        window.updateContentsScale()

        place(head: head)
        window.show()
        let pop = CABasicAnimation(keyPath: "opacity")
        pop.fromValue = 0
        pop.toValue = 1
        pop.duration = 0.15
        window.rootLayer.add(pop, forKey: "in")

        Self.live[ObjectIdentifier(self)] = self
        schedule(after: Self.readingTime(text))
    }

    /// Where the bubble goes for a head at `head` inside `area`: centred above the head, slid inside the area.
    /// Returns the bubble rect and the tail's x (both global).
    static func layout(size: CGSize, head: CGPoint, area: CGRect) -> (rect: CGRect, tailX: CGFloat) {
        var x = head.x - size.width / 2
        x = min(x, area.maxX - size.width - 2)
        x = max(x, area.minX + 2)
        var y = head.y + tail + 2
        y = min(y, area.maxY - size.height - 1)
        y = max(y, area.minY + tail + 1)
        let r = CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        return (r, min(max(head.x, r.minX + 12), r.maxX - 12).rounded())
    }

    /// Called every frame with the pet's head (global).
    func follow(head: CGPoint) {
        guard !isClosed else { return }
        place(head: head)
    }

    private func place(head: CGPoint) {
        let (r, tx) = Self.layout(size: size, head: head, area: display.visibleFrame)
        let m = Self.margin
        window.setFrameOrigin(CGPoint(x: r.minX - m, y: r.minY - Self.tail - m), clip: display.frame)
        guard tx != tailX else { return }
        tailX = tx
        // Window space: the bubble starts at (m, m + tail); the tail points down from its bottom edge.
        let local = CGRect(x: m, y: m + Self.tail, width: size.width, height: size.height)
        let t = tx - r.minX + m
        let path = CGMutablePath()
        path.addRoundedRect(in: local, cornerWidth: 8, cornerHeight: 8)
        path.move(to: CGPoint(x: t - 6, y: local.minY + 0.5))
        path.addLine(to: CGPoint(x: t, y: local.minY - Self.tail))
        path.addLine(to: CGPoint(x: t + 6, y: local.minY + 0.5))
        shape.path = path
    }

    private func schedule(after seconds: Double) {
        fadeTimer?.invalidate()
        closeTimer?.invalidate()
        let fade = max(seconds - 0.3, 0)
        fadeTimer = Timer.scheduledTimer(withTimeInterval: fade, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeOut(duration: 0.3) }
        }
        closeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func fadeOut(duration: Double) {
        guard !isClosed else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = window.rootLayer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = duration
        window.rootLayer.opacity = 0
        window.rootLayer.add(fade, forKey: "out")
    }

    /// Gone now (a newer line, or the pet left).
    func remove() {
        guard !isClosed else { return }
        fadeOut(duration: 0.15)
        fadeTimer?.invalidate()
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        fadeTimer?.invalidate()
        closeTimer?.invalidate()
        window.close()
        Self.live[ObjectIdentifier(self)] = nil
    }
}
