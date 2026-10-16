import AppKit
import PetCore
import PetPlatform
import SwiftUI

/// Summon now · Summon ▸ <pet> ▸ <scene> · Pause · Settings · Debug ▸ · Quit
struct MenuBarContent: View {
    let engine: PetEngine
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var store = engine.settingsStore

        Text(status)
        if engine.appearancesToday > 0 {
            Text("\(engine.appearancesToday) appearance\(engine.appearancesToday == 1 ? "" : "s") today")
        }
        if engine.settings.aiEnabled {
            let ai = engine.aiUsageToday
            Text("AI: \(ai.calls) call\(ai.calls == 1 ? "" : "s") today" + (ai.skipped > 0 ? ", \(ai.skipped) skipped" : ""))
        }
        Divider()

        Button("Summon Now") { engine.summonRandom() }
            .disabled(engine.packs.isEmpty || engine.isPlaying)
        Button("Summon Together") { engine.summonTogether() }
            .disabled(engine.enabledPacks.count < 2 || engine.isPlaying)
        Menu("Summon") {
            ForEach(engine.packs) { pack in
                Menu(pack.name) {
                    ForEach(pack.data.scenes) { scene in
                        Button("\(scene.name)  ·  \(scene.tier.rawValue)") {
                            engine.summon(petID: pack.id, sceneID: scene.id)
                        }
                    }
                }
            }
        }
        .disabled(engine.packs.isEmpty || engine.isPlaying)
        Menu("Summon Interaction") {
            ForEach(engine.playableEnsembles) { e in
                Button("\(e.name)  ·  \(e.tier.rawValue)") { engine.summonEnsemble(e.id) }
            }
        }
        .disabled(engine.playableEnsembles.isEmpty || engine.isPlaying)
        Menu("Pets") {
            Picker("Appear", selection: $store.settings.petMode) {
                Text("Mix of Enabled Pets").tag(PetMode.mix)
                Text("Only One Pet").tag(PetMode.single)
            }
            .pickerStyle(.inline)
            Divider()
            if store.settings.petMode == .single {
                Picker("Pet", selection: singlePet) {
                    ForEach(engine.enabledPacks) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.inline)
            } else {
                ForEach(engine.packs) { pack in
                    Toggle(pack.name, isOn: Binding(get: { engine.isEnabled(pack.id) },
                                                    set: { engine.setEnabled(pack.id, $0) }))
                }
                Divider()
                Picker("Together", selection: $store.settings.togetherChance) {
                    Text("Never Together").tag(0.0)
                    Text("Sometimes Together").tag(0.15)
                    Text("Often Together").tag(0.4)
                    Text("Always Together").tag(1.0)
                }
                .pickerStyle(.inline)
            }
        }
        Divider()

        if engine.isPaused {
            Button("Resume") { engine.resume() }
        } else {
            Button("Pause for 1 Hour") { engine.pause(for: 3600) }
            Button("Pause Until Tomorrow") { engine.pauseUntilTomorrow() }
        }
        Toggle("Pets Enabled", isOn: $store.settings.enabled)
        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Menu("Debug") {
            Button("Show Static Pet (5 s)") { engine.summonStatic() }
            Button("Fire Scheduler Now") { engine.fireNow() }
            Toggle("Outline Pet Window", isOn: $store.settings.debugOutlineWindow)
            Toggle("Allow Over Full-Screen Apps", isOn: $store.settings.debugAllowOverFullScreen)
            Divider()
            Toggle("Show Context Overlay", isOn: Binding(get: { engine.showDebugOverlay }, set: { engine.showDebugOverlay = $0 }))
            Text("Context: \(engine.contextState.rawValue)\(engine.contextReason.map { " · \($0)" } ?? "")")
            if let gate = engine.lastGate { Text("Last gate: \(gate.label)") }
            Button("Reload Pet Packs") { engine.reloadPacks() }
            Button("Show Welcome / Permissions") { Onboarding.show() }
            Button("Reveal History File") { NSWorkspace.shared.activateFileViewerSelecting([engine.historyURL]) }
        }
        Divider()
        Button("Quit Ambient Pets") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// The "Only one" pet, defaulting to the first enabled pet when none is chosen yet.
    private var singlePet: Binding<String?> {
        Binding(get: { engine.activePacks.first?.id ?? engine.settings.singlePetID },
                set: { engine.settingsStore.settings.singlePetID = $0 })
    }

    private var status: String {
        if engine.packs.isEmpty { return "No pet packs loaded" }
        if let scene = engine.currentScene { return "Playing: \(scene)" }
        if !engine.settings.enabled { return "Pets disabled" }
        if engine.isPaused, let until = engine.pausedUntil {
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        guard let next = engine.nextAppearance else { return engine.lastGate?.label ?? "Waiting" }
        let minutes = Int((next.timeIntervalSinceNow / 60).rounded())
        let when = minutes < 1 ? "under a minute" : "~\(minutes) min"
        if let gate = engine.lastGate { return "\(gate.label) · retry in \(when)" }
        return "Next appearance in \(when)"
    }
}
