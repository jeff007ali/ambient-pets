import AppKit
import QuartzCore

/// A small rounded bubble above the pet's head, auto-sized to its text, shown for a few seconds.
@MainActor
final class SpeechBubble {
    private let layer = CALayer()
    private var remaining: Double

    static let maxTextWidth: CGFloat = 170
    static let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)

    /// - Parameters:
    ///   - headTop: top of the sprite above the pivot, points.
    ///   - windowSize / pivot: to keep the bubble inside the window.
    init(text: String, in overlay: CALayer, headTop: CGFloat, pivot: CGPoint, windowSize: CGSize,
         duration: Double = 2.6, contentsScale: CGFloat) {
        remaining = duration
        let attributed = NSAttributedString(string: text, attributes: [.font: Self.font])
        let textSize = attributed.boundingRect(with: CGSize(width: Self.maxTextWidth, height: 200),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading]).integral.size
        let pad = CGSize(width: 9, height: 5), tail: CGFloat = 6
        let size = CGSize(width: textSize.width + pad.width * 2, height: textSize.height + pad.height * 2)

        // Bubble rect in overlay space (origin = pivot), clamped to the window horizontally.
        var x = -size.width / 2
        x = max(x, -pivot.x + 2)
        x = min(x, windowSize.width - pivot.x - size.width - 2)
        let y = min(headTop + tail + 2, windowSize.height - pivot.y - size.height - 1)
        let rect = CGRect(x: x, y: y, width: size.width, height: size.height)

        let shape = CAShapeLayer()
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: 7, cornerHeight: 7)
        let tailX = min(max(0, rect.minX + 10), rect.maxX - 10)
        path.move(to: CGPoint(x: tailX - 5, y: rect.minY + 0.5))
        path.addLine(to: CGPoint(x: tailX, y: rect.minY - tail))
        path.addLine(to: CGPoint(x: tailX + 5, y: rect.minY + 0.5))
        shape.path = path
        shape.fillColor = NSColor(white: 1, alpha: 0.97).cgColor
        shape.strokeColor = NSColor(white: 0.15, alpha: 0.9).cgColor
        shape.lineWidth = 1
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowOpacity = 0.25
        shape.shadowRadius = 2
        shape.shadowOffset = CGSize(width: 0, height: -1)

        let label = CATextLayer()
        label.string = attributed
        label.isWrapped = true
        label.alignmentMode = .center
        label.contentsScale = contentsScale
        label.frame = CGRect(x: rect.minX + pad.width, y: rect.minY + pad.height - 1, width: textSize.width, height: textSize.height)
        label.foregroundColor = NSColor.black.cgColor

        layer.actions = noImplicitActions()
        layer.addSublayer(shape)
        layer.addSublayer(label)
        overlay.addSublayer(layer)

        let pop = CABasicAnimation(keyPath: "opacity")
        pop.fromValue = 0
        pop.toValue = 1
        pop.duration = 0.15
        layer.add(pop, forKey: "in")
    }

    /// Returns false once the bubble has gone.
    func update(dt: Double) -> Bool {
        remaining -= dt
        if remaining <= 0 {
            layer.removeFromSuperlayer()
            return false
        }
        if remaining < 0.25, layer.animation(forKey: "out") == nil {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.25
            layer.opacity = 0
            layer.add(fade, forKey: "out")
        }
        return true
    }

    func remove() { layer.removeFromSuperlayer() }
}
