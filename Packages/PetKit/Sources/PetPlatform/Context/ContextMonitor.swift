import AppKit
import ApplicationServices
import CoreAudio
import CoreMediaIO
import PetCore

/// Reads what the user is doing (plan §4.4). Nothing here polls on its own: signals are sampled when an appearance
/// is about to fire and about once a second while a scene plays. Every check degrades gracefully: without
/// Accessibility there is no caret avoidance, without Screen Recording no window-title matching.
@MainActor
public final class ContextMonitor {
    public init() {}

    // MARK: - Permissions

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }
    public static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    // MARK: - Signals

    public struct Snapshot: Sendable {
        public var signals: ContextSignals
        public var obstacles: [Obstacle]
    }

    /// Full snapshot: classification inputs plus obstacles (AppKit coordinates).
    public func snapshot(settings: AppSettings, idleSeconds: Double, sinceKeystroke: Double, locked: Bool,
                         displays: [DisplayGeometry]) -> Snapshot {
        var s = ContextSignals(idleSeconds: idleSeconds, isLocked: locked)
        s.secondsSinceKeystroke = sinceKeystroke
        let front = NSWorkspace.shared.frontmostApplication
        let bundle = front?.bundleIdentifier
        s.frontmostBundleID = bundle
        let windows = Self.onScreenWindows()
        let primaryHeight = CoordinateSpace.primaryHeight(of: displays)
        let full = front.map { Self.isFullScreen(pid: $0.processIdentifier, windows: windows, displays: displays, primaryHeight: primaryHeight) } ?? false
        s.frontmostIsFullScreen = full
        s.isGaming = front.map { Self.isGame($0, extra: settings.gameBundleIDs) } ?? false
        s.isPresenting = full && bundle.map { settings.presentationBundleIDs.contains($0) } == true
            || (full && Self.titleMatches(windows: windows, pid: front?.processIdentifier, keywords: ["Google Slides", "Slideshow", "Presenter View"]))
        s.meetingReason = Self.meetingReason(settings: settings, windows: windows)
        s.inMeeting = s.meetingReason != nil
        s.frontmostIsReadingApp = bundle.map { settings.readingBundleIDs.contains($0) } ?? false

        var obstacles: [Obstacle] = []
        if settings.avoidUI {
            obstacles += Self.caretObstacles(primaryHeight: primaryHeight)
            let m = NSEvent.mouseLocation
            obstacles.append(Obstacle(rect: CGRect(x: m.x - 150, y: m.y - 150, width: 300, height: 300), kind: .cursor))
            if let pid = front?.processIdentifier, let r = Self.mainWindowRect(pid: pid, windows: windows, primaryHeight: primaryHeight) {
                obstacles.append(Obstacle(rect: r, kind: .activeWindow))
            }
        }
        return Snapshot(signals: s, obstacles: obstacles)
    }

    // MARK: - Windows

    typealias WindowInfo = [String: Any]

    static func onScreenWindows() -> [WindowInfo] {
        (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [WindowInfo]) ?? []
    }

    static func bounds(_ w: WindowInfo) -> CGRect? {
        guard let d = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: d)
    }

    static func ownerPID(_ w: WindowInfo) -> pid_t? { (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value }
    static func layer(_ w: WindowInfo) -> Int { (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0 }

    /// The frontmost app has a normal-layer window exactly covering a display (native full screen, or a borderless
    /// full-screen game / player).
    static func isFullScreen(pid: pid_t, windows: [WindowInfo], displays: [DisplayGeometry], primaryHeight: CGFloat) -> Bool {
        let screens = displays.map { CoordinateSpace.appKitToCG($0.frame, primaryHeight: primaryHeight) }
        for w in windows where ownerPID(w) == pid && layer(w) == 0 {
            guard let b = bounds(w) else { continue }
            if screens.contains(where: { abs($0.minX - b.minX) < 2 && abs($0.minY - b.minY) < 2 && abs($0.width - b.width) < 2 && abs($0.height - b.height) < 2 }) {
                return true
            }
        }
        return false
    }

    static func mainWindowRect(pid: pid_t, windows: [WindowInfo], primaryHeight: CGFloat) -> CGRect? {
        // CGWindowList is front-to-back: the first sizeable normal-layer window of the app is its main window
        // (skipping toolbars, popovers and other thin helper windows).
        for w in windows where ownerPID(w) == pid && layer(w) == 0 {
            guard let b = bounds(w), b.width >= 200, b.height >= 150 else { continue }
            return CoordinateSpace.cgToAppKit(b, primaryHeight: primaryHeight)
        }
        return nil
    }

    /// Window titles are only readable with Screen Recording; without it this quietly returns false.
    static func titleMatches(windows: [WindowInfo], pid: pid_t?, keywords: [String], owners: Set<String>? = nil) -> Bool {
        guard hasScreenRecording else { return false }
        for w in windows where layer(w) == 0 {
            if let pid, ownerPID(w) != pid { continue }
            if let owners, let name = w[kCGWindowOwnerName as String] as? String, !owners.contains(name) { continue }
            guard let title = w[kCGWindowName as String] as? String, !title.isEmpty else { continue }
            if keywords.contains(where: { title.localizedCaseInsensitiveContains($0) }) { return true }
        }
        return false
    }

    // MARK: - Games

    static func isGame(_ app: NSRunningApplication, extra: [String]) -> Bool {
        if let id = app.bundleIdentifier, extra.contains(id) { return true }
        guard let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary else { return false }
        let category = (info["LSApplicationCategoryType"] as? String) ?? ""
        return category.contains("games")
    }

    // MARK: - Meetings

    /// Microphone or camera in use by another process is the strong signal; a meeting window title (Zoom, Meet,
    /// Teams, Webex…) is the backup when Screen Recording is granted.
    static func meetingReason(settings: AppSettings, windows: [WindowInfo]) -> String? {
        if microphoneInUse() { return "microphone in use" }
        if cameraInUse() { return "camera in use" }
        let meetingApps = Set(NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier.map { settings.meetingBundleIDs.contains($0) || AppSettings.browserApps.contains($0) } ?? false
        }.compactMap(\.localizedName))
        if !meetingApps.isEmpty, titleMatches(windows: windows, pid: nil, keywords: settings.meetingTitleKeywords, owners: meetingApps) {
            return "meeting window open"
        }
        return nil
    }

    /// Any *other* process capturing audio input (macOS 14.2+ process objects), else any input device running.
    static func microphoneInUse() -> Bool {
        if #available(macOS 14.2, *) {
            let me = ProcessInfo.processInfo.processIdentifier
            for process in audioObjects(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyProcessObjectList) {
                guard audioUInt32(process, selector: kAudioProcessPropertyIsRunningInput) == 1 else { continue }
                if audioInt32(process, selector: kAudioProcessPropertyPID) != me { return true }
            }
            return false
        }
        return audioObjects(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices).contains { device in
            hasInputStreams(device) && audioUInt32(device, selector: kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
        }
    }

    static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0 else { return false }
        for device in devices {
            var running: UInt32 = 0
            var runningAddress = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                           mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                           mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioObjects(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func audioUInt32(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var a = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func audioInt32(_ object: AudioObjectID, selector: AudioObjectPropertySelector) -> Int32? {
        var a = address(selector)
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        return AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var a = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr && size > 0
    }

    // MARK: - Caret / focused element (Accessibility)

    /// The caret's neighbourhood (blocking) and the focused text field (soft). Empty without Accessibility.
    static func caretObstacles(primaryHeight: CGFloat) -> [Obstacle] {
        guard hasAccessibility else { return [] }
        let system = AXUIElementCreateSystemWide()
        // A hung app must never stall the pets.
        AXUIElementSetMessagingTimeout(system, 0.1)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return [] }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.1)
        var out: [Obstacle] = []

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success, let rangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boundsRef) == .success,
               let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() {
                var r = CGRect.zero
                if AXValueGetValue(boundsRef as! AXValue, .cgRect, &r), r.width < 4000, r.height < 4000 {
                    let caret = CoordinateSpace.cgToAppKit(r, primaryHeight: primaryHeight).insetBy(dx: -90, dy: -60)
                    out.append(Obstacle(rect: caret, kind: .caret))
                }
            }
        }
        if let frame = elementFrame(element, primaryHeight: primaryHeight) {
            out.append(Obstacle(rect: frame, kind: .cursor))
        }
        return out
    }

    static func elementFrame(_ element: AXUIElement, primaryHeight: CGFloat) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var p = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &p), AXValueGetValue(sizeRef as! AXValue, .cgSize, &sz),
              sz.width > 0, sz.height > 0 else { return nil }
        return CoordinateSpace.cgToAppKit(CGRect(origin: p, size: sz), primaryHeight: primaryHeight)
    }
}
