import PetCore
import PetPlatform
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let engine: PetEngine

    var body: some View {
        TabView {
            GeneralTab(engine: engine).tabItem { Label("General", systemImage: "gearshape") }
            FrequencyTab(store: engine.settingsStore).tabItem { Label("Frequency", systemImage: "clock") }
            BehaviorTab(store: engine.settingsStore).tabItem { Label("Behavior", systemImage: "theatermasks") }
            ContextTab(engine: engine).tabItem { Label("Context", systemImage: "eye") }
            PermissionsView().tabItem { Label("Permissions", systemImage: "lock.shield") }
            AITab(engine: engine).tabItem { Label("AI", systemImage: "sparkle") }
            QuietHoursTab(store: engine.settingsStore).tabItem { Label("Quiet Hours", systemImage: "moon") }
            PerformanceTab(store: engine.settingsStore).tabItem { Label("Performance", systemImage: "speedometer") }
            PetsTab(engine: engine).tabItem { Label("Pets", systemImage: "pawprint") }
        }
        .frame(width: 560)
        .padding(.vertical, 8)
    }
}

/// Launch-at-login state. (An `@Observable` object instead of `@State`: the SwiftUI macro plugin ships only with
/// Xcode, and this target must build with just the Command Line Tools.)
@MainActor
@Observable
final class LoginItem {
    static let shared = LoginItem()
    private(set) var enabled = SMAppService.mainApp.status == .enabled
    private(set) var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}

private struct GeneralTab: View {
    let engine: PetEngine
    private let login = LoginItem.shared

    var body: some View {
        @Bindable var store = engine.settingsStore
        Form {
            Toggle("Enable pets", isOn: $store.settings.enabled)
            Toggle("Speech bubbles", isOn: $store.settings.speechBubbles)
            LabeledContent("Pet size") {
                HStack {
                    Slider(value: $store.settings.petScale, in: AppSettings.scaleRange, step: 0.05)
                    Text("\(Int((store.settings.petScale * 100).rounded())) %").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
            if let error = login.error { Text(error).font(.caption).foregroundStyle(.red) }
            Section {
                Button("Reset All Settings…") { store.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct FrequencyTab: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Stepper(value: $store.settings.minIntervalMinutes, in: 1...120, step: 1) {
                    LabeledContent("Minimum interval", value: "\(Int(store.settings.minIntervalMinutes)) min")
                }
                Stepper(value: $store.settings.maxIntervalMinutes, in: 1...240, step: 1) {
                    LabeledContent("Maximum interval", value: "\(Int(store.settings.maxIntervalMinutes)) min")
                }
                Stepper(value: $store.settings.cooldownMinutes, in: 0...60, step: 1) {
                    LabeledContent("Minimum gap", value: "\(Int(store.settings.cooldownMinutes)) min")
                }
                Stepper(value: $store.settings.dailyLimit, in: 0...200, step: 5) {
                    LabeledContent("Daily limit", value: store.settings.dailyLimit == 0 ? "Unlimited" : "\(store.settings.dailyLimit)")
                }
            } footer: {
                Text("Intervals are random between the minimum and maximum, then scaled by what you're doing: rarer while you work, more often when you're away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorTab: View {
    @Bindable var store: SettingsStore

    private func tier(_ t: SceneTier) -> Binding<Bool> {
        Binding(get: { store.settings.enabledTiers.contains(t) },
                set: { on in
                    if on { store.settings.enabledTiers.insert(t) } else { store.settings.enabledTiers.remove(t) }
                })
    }

    var body: some View {
        Form {
            Section("Scenes") {
                Toggle("Quick cameos", isOn: tier(.quick))
                Toggle("Funny interactions", isOn: tier(.funny))
                Toggle("Elaborate scenes", isOn: tier(.elaborate))
                Toggle("Rare events", isOn: tier(.rare))
            }
            Section("Interaction") {
                Toggle("React to cursor", isOn: $store.settings.reactToCursor)
                Toggle("Cross-monitor scenes", isOn: $store.settings.crossMonitorScenes)
            }
            Section {
                Toggle("Sounds", isOn: $store.settings.soundsEnabled)
                Slider(value: $store.settings.volume, in: 0...1) { Text("Volume") }.disabled(!store.settings.soundsEnabled)
                Toggle("Only when I'm away from the keyboard", isOn: $store.settings.soundsOnlyWhenIdle).disabled(!store.settings.soundsEnabled)
                Toggle("Never during meetings", isOn: $store.settings.muteSoundsInMeetings).disabled(!store.settings.soundsEnabled)
            } header: {
                Text("Audio")
            } footer: {
                Text("Off by default. Never while you're actively working, and quiet hours mute everything.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ContextTab: View {
    let engine: PetEngine

    private func frequency(_ state: ContextState, default d: Double) -> Binding<Double> {
        Binding(get: { engine.settings.contextFrequency[state.rawValue] ?? d },
                set: { engine.settingsStore.settings.contextFrequency[state.rawValue] = $0 })
    }

    private func list(_ keyPath: WritableKeyPath<AppSettings, [String]>) -> Binding<String> {
        Binding(get: { engine.settings[keyPath: keyPath].joined(separator: "\n") },
                set: { text in
                    engine.settingsStore.settings[keyPath: keyPath] = text.split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                })
    }

    var body: some View {
        @Bindable var store = engine.settingsStore
        Form {
            Section("Right now") {
                LabeledContent("Context", value: engine.contextState.rawValue)
                if let reason = engine.contextReason { LabeledContent("Because", value: reason) }
                Button("Refresh") { engine.refreshContext() }
            }
            Section {
                Toggle("Pause during full-screen apps", isOn: $store.settings.pauseDuringFullScreen)
                Toggle("Pause during meetings (microphone / camera in use, meeting windows)", isOn: $store.settings.pauseDuringMeetings)
                Toggle("Pause while gaming", isOn: $store.settings.pauseWhileGaming)
                Toggle("Keep away from the text cursor and the mouse pointer", isOn: $store.settings.avoidUI)
            } header: {
                Text("When to stay away")
            } footer: {
                Text("Presentations and a locked screen always pause pets.").font(.caption).foregroundStyle(.secondary)
            }
            Section("How often, by activity") {
                freqRow("Working", frequency(.activeWork, default: 0.6))
                freqRow("Reading", frequency(.reading, default: 0.8))
                freqRow("Away (idle)", frequency(.idle, default: 1.5))
            }
            Section {
                DisclosureGroup("Meeting apps") { TextEditor(text: list(\.meetingBundleIDs)).frame(height: 70).font(.caption.monospaced()) }
                DisclosureGroup("Meeting window titles") { TextEditor(text: list(\.meetingTitleKeywords)).frame(height: 70).font(.caption.monospaced()) }
                DisclosureGroup("Presentation apps") { TextEditor(text: list(\.presentationBundleIDs)).frame(height: 50).font(.caption.monospaced()) }
                DisclosureGroup("Extra games") { TextEditor(text: list(\.gameBundleIDs)).frame(height: 50).font(.caption.monospaced()) }
                DisclosureGroup("Reading apps") { TextEditor(text: list(\.readingBundleIDs)).frame(height: 70).font(.caption.monospaced()) }
            } header: {
                Text("Apps")
            } footer: {
                Text("One bundle id (or title keyword) per line. Games are also recognised from their App Store category.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func freqRow(_ name: String, _ value: Binding<Double>) -> some View {
        LabeledContent(name) {
            HStack {
                Slider(value: value, in: 0.1...3)
                Text(String(format: "%.1f×", value.wrappedValue)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
    }
}

/// Draft API key text (an object instead of `@State`, which needs a macro plugin the CLT lack).
@MainActor
@Observable
final class AIKeyDraft {
    static let shared = AIKeyDraft()
    var text = ""
    var refresh = 0
    var testing = false
    var testResult: String?
}

private struct AITab: View {
    let engine: PetEngine
    private let draft = AIKeyDraft.shared

    var body: some View {
        @Bindable var store = engine.settingsStore
        @Bindable var draft = draft
        let provider = store.settings.aiProvider
        let hasKey = { _ = draft.refresh; return AIKeychain.hasKey(provider) }()
        Form {
            Section {
                Toggle("Let AI pick scenes", isOn: $store.settings.aiEnabled)
                Picker("Provider", selection: $store.settings.aiProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Model") {
                    HStack {
                        TextField("model id", text: $store.settings.aiModel).font(.body.monospaced())
                        Menu("Presets") {
                            ForEach(provider.suggestedModels, id: \.self) { m in Button(m) { store.settings.aiModel = m } }
                        }
                        .fixedSize()
                    }
                }
                Toggle("Let it write the occasional speech line", isOn: $store.settings.aiSpeech)
                Toggle("Let it choose interactions when pets come together", isOn: $store.settings.aiInteractions)
                Toggle("Let it invent new routines from each pet's moves", isOn: $store.settings.aiRoutines)
                Toggle("Give each pet a mood for the day", isOn: $store.settings.aiMoods)
                Toggle("Share the frontmost window title (needs Screen Recording)", isOn: $store.settings.aiShareWindowTitles)
            } footer: {
                Text("Off by default. The AI only chooses among scenes that already passed every rule (quiet hours, meetings, limits) and is asked at most once per appearance; if it's slow (over 2 s) or anything fails, the normal picker is used.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("\(provider.displayName) API key") {
                if hasKey {
                    LabeledContent("API key", value: "Saved in Keychain")
                    Button("Remove Key", role: .destructive) {
                        AIKeychain.delete(provider)
                        draft.refresh += 1
                    }
                } else {
                    SecureField(provider == .openai ? "sk-…" : "sk-ant-…", text: $draft.text)
                    Button("Save to Keychain") {
                        AIKeychain.save(draft.text, for: provider)
                        draft.text = ""
                        draft.refresh += 1
                    }
                    .disabled(draft.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack {
                    Button(draft.testing ? "Testing…" : "Test") {
                        draft.testing = true
                        Task { @MainActor in
                            draft.testResult = await engine.testAI()
                            draft.testing = false
                        }
                    }
                    .disabled(!hasKey || draft.testing)
                    if let r = draft.testResult ?? engine.lastAIResult { Text(r).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                }
            }
            Section("What is sent") {
                Text("The activity (e.g. WORKING), the frontmost app's category (e.g. developer-tools — not its name), the time of day and weekday, general stats (minutes focused or away, cameos today), your last five scenes, the pets' moods, and the candidate scenes and moves. Window titles only if you turn that on above. Nothing else: no screenshots, text, or file names.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { draft.refresh += 1 }
    }
}

private struct QuietHoursTab: View {
    @Bindable var store: SettingsStore

    private func time(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = store.settings.quietHours[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                store.settings.quietHours[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Quiet hours", isOn: $store.settings.quietHours.enabled)
                DatePicker("From", selection: time(\.startMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!store.settings.quietHours.enabled)
                DatePicker("Until", selection: time(\.endMinutes), displayedComponents: .hourAndMinute)
                    .disabled(!store.settings.quietHours.enabled)
            } footer: {
                Text("No pets, sounds or animations during quiet hours. Ranges may span midnight, e.g. 22:00–08:00.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PerformanceTab: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Picker("Maximum FPS", selection: $store.settings.maxFPS) {
                ForEach([15, 24, 30, 60], id: \.self) { Text("\($0)").tag($0) }
            }
            Toggle("Reduce animation quality", isOn: $store.settings.reduceQuality)
            Toggle("Skip appearances when the Mac is hot or in Low Power Mode", isOn: $store.settings.skipUnderLoad)
        }
        .formStyle(.grouped)
    }
}

private struct PetsTab: View {
    let engine: PetEngine

    private var singlePet: Binding<String?> {
        Binding(get: { engine.activePacks.first?.id ?? engine.settings.singlePetID },
                set: { engine.settingsStore.settings.singlePetID = $0 })
    }

    var body: some View {
        @Bindable var store = engine.settingsStore
        Form {
            Section {
                Picker("Pets appear", selection: $store.settings.petMode) {
                    Text("Mix of enabled pets").tag(PetMode.mix)
                    Text("Only one pet").tag(PetMode.single)
                }
                if store.settings.petMode == .single {
                    Picker("Pet", selection: singlePet) {
                        ForEach(engine.enabledPacks) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            Section("Pets") {
                if engine.packs.isEmpty { Text("No packs loaded.").foregroundStyle(.secondary) }
                ForEach(engine.packs) { pack in
                    Toggle(isOn: Binding(get: { engine.isEnabled(pack.id) }, set: { engine.setEnabled(pack.id, $0) })) {
                        VStack(alignment: .leading) {
                            Text(pack.name)
                            Text("\(pack.data.scenes.count) scenes · v\(pack.data.definition.version ?? "?")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("How often") {
                        HStack {
                            Slider(value: Binding(get: { engine.settings.petWeights[pack.id] ?? 1 },
                                                  set: { engine.settingsStore.settings.petWeights[pack.id] = $0 }), in: 0.25...3)
                            Text(String(format: "%.2g×", engine.settings.petWeights[pack.id] ?? 1)).monospacedDigit().frame(width: 40)
                        }
                    }
                    .disabled(!engine.isEnabled(pack.id))
                    .padding(.leading, 18)
                }
            }
            Section {
                Picker("Appear together", selection: $store.settings.togetherChance) {
                    Text("Never").tag(0.0)
                    Text("Sometimes").tag(0.15)
                    Text("Often").tag(0.4)
                    Text("Always").tag(1.0)
                }
                .disabled(store.settings.petMode == .single)
                Picker("When together, interact", selection: $store.settings.interactionChance) {
                    Text("Never (separate scenes)").tag(0.0)
                    Text("Sometimes").tag(0.5)
                    Text("Always").tag(1.0)
                }
                .disabled(store.settings.petMode == .single)
                Stepper(value: $store.settings.maxTogether, in: AppSettings.togetherRange) {
                    LabeledContent("Up to", value: "\(store.settings.maxTogether) pets at once")
                }
                .disabled(store.settings.petMode == .single)
                Button("Summon Together Now") { engine.summonTogether() }
                    .disabled(engine.enabledPacks.count < 2 || engine.isPlaying)
            } header: {
                Text("Together")
            } footer: {
                Text("When pets come together, each one plays its own scene in its own part of the screen. Needs \"Mix of enabled pets\" and at least two enabled pets.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !engine.loadFailures.isEmpty {
                Section("Skipped (invalid)") {
                    ForEach(engine.loadFailures, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                }
            }
            Section {
                Button("Reload Packs") { engine.reloadPacks() }
                Button("Open User Pets Folder") {
                    try? FileManager.default.createDirectory(at: PetDirectories.user, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(PetDirectories.user)
                }
            } footer: {
                Text("Add your own packs to ~/Library/Application Support/AmbientPets/Pets.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
