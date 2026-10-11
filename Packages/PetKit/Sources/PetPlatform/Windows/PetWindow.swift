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
    public var rootLayer: CALayer { hostView.layer! }
    private var backingObserver: NSObjectProtocol?

    public init(size: CGSize, outline: Bool = false) {
        panel = PetPanel(size: size)
        hostView = PetHostView(frame: CGRect(origin: .zero, size: size))
        panel.contentView = hostView
        if outline {
            rootLayer.borderColor = NSColor.systemPink.cgColor
            rootLayer.borderWidth = 1
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
        apply(rootLayer)
    }

    public var backingScale: CGFloat { panel.backingScaleFactor }

    public func setFrameOrigin(_ origin: CGPoint) {
        panel.setFrameOrigin(origin)
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
