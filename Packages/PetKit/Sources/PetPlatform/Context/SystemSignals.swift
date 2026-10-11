import AppKit
import CoreGraphics
import PetCore

/// Permission-free context signals: idle time, screen lock, sleep/wake, thermal and power state.
/// Event-driven; idle time is sampled only when asked (at fire time), never polled.
/// The richer monitors (full-screen, meetings, games, AX focus) arrive in M5 behind the same `ContextSignals`.
@MainActor
public final class SystemSignals {
    public private(set) var isLocked = false
    /// Lock, unlock, wake, or thermal change. The engine reschedules or aborts.
    public var onChange: ((Event) -> Void)?

    public enum Event: Sendable { case locked, unlocked, willSleep, didWake, loadChanged }

    public init() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isLocked = true; self?.onChange?(.locked) }
        }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isLocked = false; self?.onChange?(.unlocked) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?(.willSleep) }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?(.didWake) }
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?(.willSleep) }
        }
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?(.loadChanged) }
            }
        }
    }

    /// Seconds since the last keyboard, mouse or scroll input (no permission needed).
    public func idleSeconds() -> Double {
        let types: [CGEventType] = [.keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown,
                                    .otherMouseDown, .scrollWheel, .leftMouseDragged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    /// Thermal state serious or worse, or Low Power Mode.
    public var underLoad: Bool {
        let p = ProcessInfo.processInfo
        return p.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue || p.isLowPowerModeEnabled
    }

    /// Seconds since the last key press.
    public func secondsSinceKeystroke() -> Double {
        min(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .flagsChanged))
    }

    public func signals() -> ContextSignals {
        ContextSignals(idleSeconds: idleSeconds(), isLocked: isLocked)
    }
}
