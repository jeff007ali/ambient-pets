import AppKit
import PetCore

/// Connected displays in AppKit global coordinates, refreshed on screen-parameter changes.
@MainActor
public final class ScreenManager {
    public private(set) var displays: [DisplayGeometry] = []
    /// Called after the display list changes (plug, unplug, resolution, arrangement, Dock moves).
    public var onChange: (() -> Void)?

    public init() {
        refresh()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.onChange?()
            }
        }
    }

    public func refresh() {
        displays = NSScreen.screens.map(Self.geometry)
    }

    public static func geometry(of screen: NSScreen) -> DisplayGeometry {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return DisplayGeometry(id: number?.uint32Value ?? 0, frame: screen.frame, visibleFrame: screen.visibleFrame,
                               backingScale: Double(screen.backingScaleFactor))
    }

    public func display(id: UInt32) -> DisplayGeometry? { displays.first { $0.id == id } }

    /// Uniform across connected displays (spec §5).
    public func randomDisplay(_ rng: RandomSource) -> DisplayGeometry? { rng.element(of: displays) }

    /// The display under the mouse pointer: a sensible default for on-demand summons.
    public var displayUnderMouse: DisplayGeometry? {
        let p = NSEvent.mouseLocation
        return displays.first { $0.frame.contains(p) } ?? displays.first
    }

    public var primaryHeight: CGFloat { CoordinateSpace.primaryHeight(of: displays) }
}
