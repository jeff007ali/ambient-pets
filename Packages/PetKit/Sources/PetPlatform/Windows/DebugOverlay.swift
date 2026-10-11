import AppKit
import PetCore
import QuartzCore

/// Debug view of what the engine sees: context state, obstacle rects, planner candidates and chosen anchors.
/// One click-through panel per display, refreshed only while the overlay is switched on.
@MainActor
final class DebugOverlay {
    private var panels: [UInt32: (PetPanel, CALayer)] = [:]

    func update(displays: [DisplayGeometry], state: ContextState, reason: String?, obstacles: [Obstacle],
                candidates: [CGPoint], anchors: [CGPoint]) {
        let ids = Set(displays.map(\.id))
        for (id, entry) in panels where !ids.contains(id) {
            entry.0.orderOut(nil)
            panels[id] = nil
        }
        for d in displays {
            let (panel, root) = panels[d.id] ?? makePanel(for: d)
            panels[d.id] = (panel, root)
            panel.setFrame(d.frame, display: false)
            root.sublayers?.forEach { $0.removeFromSuperlayer() }
            let local = { (r: CGRect) in r.offsetBy(dx: -d.frame.minX, dy: -d.frame.minY) }
            for o in obstacles where o.rect.intersects(d.frame) {
                root.addSublayer(rectLayer(local(o.rect), color: color(o.kind)))
            }
            for p in candidates where d.frame.contains(p) {
                root.addSublayer(dot(CGPoint(x: p.x - d.frame.minX, y: p.y - d.frame.minY), color: .systemBlue, size: 8))
            }
            for p in anchors where d.frame.contains(p) {
                root.addSublayer(dot(CGPoint(x: p.x - d.frame.minX, y: p.y - d.frame.minY), color: .systemGreen, size: 14))
            }
            let label = CATextLayer()
            label.string = "\(state.rawValue)\(reason.map { " · \($0)" } ?? "")  [obstacles \(obstacles.count)]"
            label.fontSize = 13
            label.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
            label.foregroundColor = NSColor.white.cgColor
            label.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            label.contentsScale = d.backingScale
            label.frame = CGRect(x: d.visibleFrame.minX - d.frame.minX + 12, y: d.visibleFrame.maxY - d.frame.minY - 30, width: 560, height: 20)
            root.addSublayer(label)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        for (panel, _) in panels.values { panel.orderOut(nil) }
        panels.removeAll()
    }

    private func makePanel(for d: DisplayGeometry) -> (PetPanel, CALayer) {
        let panel = PetPanel(size: d.frame.size)
        let view = PetHostView(frame: CGRect(origin: .zero, size: d.frame.size))
        panel.contentView = view
        panel.setFrame(d.frame, display: false)
        return (panel, view.layer!)
    }

    private func color(_ k: Obstacle.Kind) -> NSColor {
        switch k {
        case .caret: .systemRed
        case .cursor: .systemOrange
        case .activeWindow: .systemBlue
        case .video: .systemPurple
        }
    }

    private func rectLayer(_ r: CGRect, color: NSColor) -> CALayer {
        let l = CALayer()
        l.frame = r
        l.borderColor = color.cgColor
        l.borderWidth = 2
        l.backgroundColor = color.withAlphaComponent(0.08).cgColor
        return l
    }

    private func dot(_ p: CGPoint, color: NSColor, size: CGFloat) -> CALayer {
        let l = CALayer()
        l.frame = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        l.cornerRadius = size / 2
        l.backgroundColor = color.cgColor
        return l
    }
}
