import AppKit
import QuartzCore

/// The click-through, non-activating overlay window (plan §4.1).
///
/// It never becomes key or main, ignores all mouse events, sits above normal and floating windows, follows every
/// Space, stays out of Cmd-Tab / Cmd-` / Mission Control, and is shown only with `orderFrontRegardless()`.
public final class PetPanel: NSPanel {
    public init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Borderless panels may sit partly or fully off-screen (entering from an edge).
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Layer-hosting view that refuses hit testing (belt and braces on top of `ignoresMouseEvents`).
final class PetHostView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.actions = noImplicitActions()
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}

/// Disables implicit CA animations for properties we update every frame.
func noImplicitActions() -> [String: any CAAction] {
    let none = NSNull()
    return ["contents": none, "position": none, "bounds": none, "frame": none, "transform": none,
            "opacity": none, "hidden": none, "sublayers": none, "contentsRect": none]
}

/// Creates, positions, shows and destroys one pet window.
@MainActor
public final class PetWindowController {
    public let panel: PetPanel
    let hostView: PetHostView
    /// Everything the pet draws goes in here, in box coordinates; its bounds are the part of the box on screen.
    public let rootLayer = CALayer()
    /// The pet's full drawing area; the window may show only part of it (see `setFrameOrigin(_:clip:)`).
    private let boxSize: CGSize
    private var backingObserver: NSObjectProtocol?

    public init(size: CGSize, outline: Bool = false) {
        boxSize = size
        panel = PetPanel(size: size)
        hostView = PetHostView(frame: CGRect(origin: .zero, size: size))
        panel.contentView = hostView
        rootLayer.actions = noImplicitActions()
        rootLayer.anchorPoint = .zero
        rootLayer.masksToBounds = true
        rootLayer.frame = CGRect(origin: .zero, size: size)
        hostView.layer!.addSublayer(rootLayer)
        if outline {
            hostView.layer!.borderColor = NSColor.systemPink.cgColor
            hostView.layer!.borderWidth = 1
        }
        updateContentsScale()
        backingObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification,
                                                                 object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateContentsScale() }
        }
    }

    /// Keeps text and vector layers crisp when the window moves between Retina and non-Retina displays.
    func updateContentsScale() {
        let scale = panel.backingScaleFactor
        func apply(_ layer: CALayer) {
            layer.contentsScale = scale
            layer.sublayers?.forEach(apply)
        }
        apply(hostView.layer!)
    }

    public var backingScale: CGFloat { panel.backingScaleFactor }

    /// Places the pet's box (window-sized drawing area) with its bottom-left at `origin`. With `clip` (global
    /// coordinates), the window shrinks to the part of the box inside it and shows only that part, so a pet never
    /// spills onto a neighbouring display (stacked or side-by-side screens) and the window always renders at its
    /// own display's backing scale. Nil shows the whole box.
    public func setFrameOrigin(_ origin: CGPoint, clip: CGRect? = nil) {
        let box = CGRect(origin: origin, size: boxSize)
        let visible = clip.map { box.intersection($0) } ?? box
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else {
            // Entirely outside: keep the window where it was (inside the display) and draw nothing.
            hostView.layer!.isHidden = true
            return
        }
        hostView.layer!.isHidden = false
        if visible.size != panel.frame.size {
            panel.setFrame(visible, display: true)
        } else {
            panel.setFrameOrigin(visible.origin)
        }
        // Sublayers keep box coordinates: the root layer's bounds is the visible part of the box.
        let shown = CGRect(x: visible.minX - box.minX, y: visible.minY - box.minY, width: visible.width, height: visible.height)
        if rootLayer.bounds != shown {
            rootLayer.frame = CGRect(origin: .zero, size: visible.size)
            rootLayer.bounds = shown
        }
    }

    /// Shows without activating the app or taking focus. In debug builds, verifies the frontmost app is unchanged.
    public func show() {
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
        panel.orderFrontRegardless()
        #if DEBUG
        Task { @MainActor in
            let after = NSWorkspace.shared.frontmostApplication
            if before != after?.processIdentifier {
                log.fault("pet window changed the frontmost app to \(after?.localizedName ?? "?", privacy: .public)")
            }
        }
        #endif
    }

    public func close() {
        if let backingObserver { NotificationCenter.default.removeObserver(backingObserver) }
        backingObserver = nil
        panel.orderOut(nil)
        panel.close()
    }
}
