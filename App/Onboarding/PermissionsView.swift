import AppKit
import ApplicationServices
import Observation
import PetPlatform
import SwiftUI

/// Live permission status. Nothing is required: each missing grant only switches one feature off.
@MainActor
@Observable
final class Permissions {
    static let shared = Permissions()
    private(set) var accessibility = ContextMonitor.hasAccessibility
    private(set) var screenRecording = ContextMonitor.hasScreenRecording

    func refresh() {
        accessibility = ContextMonitor.hasAccessibility
        screenRecording = ContextMonitor.hasScreenRecording
    }

    func requestAccessibility() {
        // String key instead of kAXTrustedCheckOptionPrompt (a mutable C global, not concurrency-safe in Swift 6).
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        open("Privacy_Accessibility")
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() { open("Privacy_ScreenCapture") }
    }

    func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

struct PermissionsView: View {
    private let permissions = Permissions.shared

    var body: some View {
        Form {
            Section {
                row("Accessibility", granted: permissions.accessibility,
                    gives: "Keeps pets away from your text cursor and the field you're typing in.",
                    without: "Pets still avoid the mouse pointer and the active window, but may pass over the caret.",
                    request: permissions.requestAccessibility)
                row("Screen Recording", granted: permissions.screenRecording,
                    gives: "Reads window titles to spot meetings in browser tabs (Meet, Teams, Zoom web) and slideshows.",
                    without: "Meetings are still detected from microphone / camera use and known meeting apps.",
                    request: permissions.requestScreenRecording)
            } footer: {
                Text("Nothing is required: Ambient Pets works with no permissions at all. Microphone and camera *use* are detected without access to either. Ad-hoc signed rebuilds may make macOS forget these grants.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func row(_ name: String, granted: Bool, gives: String, without: String, request: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text(gives).font(.callout)
                if !granted { Text(without).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if granted { Text("Granted").foregroundStyle(.secondary) } else { Button("Grant…", action: request) }
        }
        .padding(.vertical, 2)
    }
}

/// First-run welcome: what the app does and the optional permissions.
@MainActor
enum Onboarding {
    private static let key = "onboarding.shown.v1"
    private static var window: NSWindow?

    static func showIfFirstRun() {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        show()
    }

    static func show() {
        let root = VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to Ambient Pets").font(.title2.bold())
            Text("Pets make short appearances now and then, from the ✨ menu bar icon. They never take focus or block clicks, and they pause during meetings, presentations, full-screen apps and games.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Two optional permissions make them more polite:").font(.headline)
            PermissionsView().frame(height: 250)
            HStack {
                Spacer()
                Button("Done") { window?.close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        let w = NSWindow(contentViewController: NSHostingController(rootView: root))
        w.title = "Ambient Pets"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}
