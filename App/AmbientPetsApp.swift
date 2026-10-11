import PetPlatform
import SwiftUI

@main
struct AmbientPetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Ambient Pets", systemImage: "sparkles") {
            MenuBarContent(engine: appDelegate.engine)
        }
        Settings {
            SettingsView(engine: appDelegate.engine)
        }
    }
}
