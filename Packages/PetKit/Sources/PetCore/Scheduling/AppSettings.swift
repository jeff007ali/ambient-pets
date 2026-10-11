import Foundation

/// Daily quiet period in local wall-clock time. `start > end` spans midnight (e.g. 22:00–08:00).
public struct QuietHours: Codable, Sendable, Hashable {
    public var enabled: Bool
    /// Minutes after midnight.
    public var startMinutes: Int
    public var endMinutes: Int

    public init(enabled: Bool = false, startMinutes: Int = 22 * 60, endMinutes: Int = 8 * 60) {
        self.enabled = enabled
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    private func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, startMinutes != endMinutes else { return false }
        let m = minuteOfDay(date, calendar)
        return startMinutes < endMinutes
            ? (m >= startMinutes && m < endMinutes)
            : (m >= startMinutes || m < endMinutes)
    }

    /// The next moment the quiet period ends, if `date` is inside it.
    public func end(after date: Date, calendar: Calendar = .current) -> Date? {
        guard contains(date, calendar: calendar) else { return nil }
        let comps = DateComponents(hour: endMinutes / 60, minute: endMinutes % 60)
        // `nextDate` follows wall-clock time, so DST shifts are handled by Calendar.
        return calendar.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
    }
}

/// Which pets may appear.
public enum PetMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// Any enabled pet, picked at random (weighted).
    case mix
    /// Only `singlePetID`.
    case single
}

/// All user settings. Every field decodes with a default, so adding a field never resets someone's settings.
public struct AppSettings: Codable, Sendable, Hashable {
    // General
    public var enabled = true
    public var speechBubbles = true
    /// User size slider, 0.5…1.5 of native sprite size.
    public var petScale = 0.8

    // Pets
    public var petMode = PetMode.mix
    public var singlePetID: String?
    public var disabledPets: Set<String> = []
    /// User "how often" per pet (multiplies the pack's own weight), 0.25…3. Missing = 1.
    public var petWeights: [String: Double] = [:]
    /// Chance (0…1) that an appearance brings several pets at once.
    public var togetherChance = 0.15
    /// How many pets come along on a "together" appearance (2…3).
    public var maxTogether = 2
    /// Chance that a together appearance is a shared scene where the pets interact (greeting, race, chase…).
    public var interactionChance = 0.5

    // Frequency
    public var minIntervalMinutes = 3.0
    public var maxIntervalMinutes = 15.0
    /// Minimum gap between two appearances, even when the context multiplier is high.
    public var cooldownMinutes = 2.0
    public var dailyLimit = 40

    // Behavior tiers
    public var enabledTiers: Set<SceneTier> = Set(SceneTier.allCases)

    // Interaction
    public var reactToCursor = true
    public var crossMonitorScenes = true

    // Audio (M5)
    public var soundsEnabled = false
    public var volume = 0.5

    // Context
    public var pauseDuringFullScreen = true
    public var pauseDuringMeetings = true
    public var pauseWhileGaming = true
    /// Seconds without input before the context becomes IDLE.
    public var idleThresholdSeconds = 120.0

    /// Per-state frequency multipliers overriding the defaults (keys: ContextState raw values).
    public var contextFrequency: [String: Double] = [:]
    /// Extra apps treated as games / meetings / presentations / reading (bundle ids), on top of detection.
    public var gameBundleIDs: [String] = []
    public var meetingBundleIDs = AppSettings.defaultMeetingApps
    public var presentationBundleIDs = AppSettings.defaultPresentationApps
    public var readingBundleIDs = AppSettings.defaultReadingApps
    /// Window-title keywords that mean a meeting (needs Screen Recording to read titles).
    public var meetingTitleKeywords = ["Zoom Meeting", "Google Meet", "Meet –", "Meet - ", "Microsoft Teams", "Webex", "FaceTime"]
    public var soundsOnlyWhenIdle = false
    public var muteSoundsInMeetings = true
    /// Avoid the text cursor / focused field and the mouse pointer (needs Accessibility for the caret).
    public var avoidUI = true

    // Optional AI chooser (M8): off by default; the API key lives in the Keychain, never here.
    public var aiEnabled = false
    public var aiProvider = AIProvider.openai
    /// Model per provider (raw value → model id); missing = the provider's default.
    public var aiModels: [String: String] = [:]
    public var aiSpeech = true
    /// The AI may also choose shared scenes / together appearances, invent routines from blocks, set daily moods.
    public var aiInteractions = true
    public var aiRoutines = true
    public var aiMoods = true
    /// Send the frontmost window's title (needs Screen Recording). Off by default.
    public var aiShareWindowTitles = false

    // Quiet hours
    public var quietHours = QuietHours()

    // Performance
    public var maxFPS = 30
    public var reduceQuality = false
    public var skipUnderLoad = true

    // Debug
    public var debugOutlineWindow = false
    public var debugAllowOverFullScreen = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, speechBubbles, petScale, petMode, singlePetID, disabledPets, petWeights, togetherChance, maxTogether, interactionChance, minIntervalMinutes, maxIntervalMinutes, cooldownMinutes, dailyLimit
        case enabledTiers, reactToCursor, crossMonitorScenes, soundsEnabled, volume
        case pauseDuringFullScreen, pauseDuringMeetings, pauseWhileGaming, idleThresholdSeconds, quietHours
        case contextFrequency, gameBundleIDs, meetingBundleIDs, presentationBundleIDs, readingBundleIDs, meetingTitleKeywords
        case soundsOnlyWhenIdle, muteSoundsInMeetings, avoidUI, aiEnabled, aiProvider, aiModels, aiSpeech, aiShareWindowTitles, aiInteractions, aiRoutines, aiMoods
        case maxFPS, reduceQuality, skipUnderLoad, debugOutlineWindow, debugAllowOverFullScreen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        enabled = try c.decode(.enabled, default: d.enabled)
        speechBubbles = try c.decode(.speechBubbles, default: d.speechBubbles)
        petScale = try c.decode(.petScale, default: d.petScale)
        petMode = try c.decode(.petMode, default: d.petMode)
        singlePetID = try c.decodeIfPresent(String.self, forKey: .singlePetID)
        disabledPets = try c.decode(.disabledPets, default: d.disabledPets)
        petWeights = try c.decode(.petWeights, default: d.petWeights)
        togetherChance = try c.decode(.togetherChance, default: d.togetherChance)
        maxTogether = try c.decode(.maxTogether, default: d.maxTogether)
        interactionChance = try c.decode(.interactionChance, default: d.interactionChance)
        minIntervalMinutes = try c.decode(.minIntervalMinutes, default: d.minIntervalMinutes)
        maxIntervalMinutes = try c.decode(.maxIntervalMinutes, default: d.maxIntervalMinutes)
        cooldownMinutes = try c.decode(.cooldownMinutes, default: d.cooldownMinutes)
        dailyLimit = try c.decode(.dailyLimit, default: d.dailyLimit)
        enabledTiers = try c.decode(.enabledTiers, default: d.enabledTiers)
        reactToCursor = try c.decode(.reactToCursor, default: d.reactToCursor)
        crossMonitorScenes = try c.decode(.crossMonitorScenes, default: d.crossMonitorScenes)
        soundsEnabled = try c.decode(.soundsEnabled, default: d.soundsEnabled)
        volume = try c.decode(.volume, default: d.volume)
        pauseDuringFullScreen = try c.decode(.pauseDuringFullScreen, default: d.pauseDuringFullScreen)
        pauseDuringMeetings = try c.decode(.pauseDuringMeetings, default: d.pauseDuringMeetings)
        pauseWhileGaming = try c.decode(.pauseWhileGaming, default: d.pauseWhileGaming)
        idleThresholdSeconds = try c.decode(.idleThresholdSeconds, default: d.idleThresholdSeconds)
        quietHours = try c.decode(.quietHours, default: d.quietHours)
        contextFrequency = try c.decode(.contextFrequency, default: d.contextFrequency)
        gameBundleIDs = try c.decode(.gameBundleIDs, default: d.gameBundleIDs)
        meetingBundleIDs = try c.decode(.meetingBundleIDs, default: d.meetingBundleIDs)
        presentationBundleIDs = try c.decode(.presentationBundleIDs, default: d.presentationBundleIDs)
        readingBundleIDs = try c.decode(.readingBundleIDs, default: d.readingBundleIDs)
        meetingTitleKeywords = try c.decode(.meetingTitleKeywords, default: d.meetingTitleKeywords)
        soundsOnlyWhenIdle = try c.decode(.soundsOnlyWhenIdle, default: d.soundsOnlyWhenIdle)
        muteSoundsInMeetings = try c.decode(.muteSoundsInMeetings, default: d.muteSoundsInMeetings)
        avoidUI = try c.decode(.avoidUI, default: d.avoidUI)
        aiEnabled = try c.decode(.aiEnabled, default: d.aiEnabled)
        aiProvider = try c.decode(.aiProvider, default: d.aiProvider)
        aiModels = try c.decode(.aiModels, default: d.aiModels)
        aiSpeech = try c.decode(.aiSpeech, default: d.aiSpeech)
        aiInteractions = try c.decode(.aiInteractions, default: d.aiInteractions)
        aiRoutines = try c.decode(.aiRoutines, default: d.aiRoutines)
        aiMoods = try c.decode(.aiMoods, default: d.aiMoods)
        aiShareWindowTitles = try c.decode(.aiShareWindowTitles, default: d.aiShareWindowTitles)
        maxFPS = try c.decode(.maxFPS, default: d.maxFPS)
        reduceQuality = try c.decode(.reduceQuality, default: d.reduceQuality)
        skipUnderLoad = try c.decode(.skipUnderLoad, default: d.skipUnderLoad)
        debugOutlineWindow = try c.decode(.debugOutlineWindow, default: d.debugOutlineWindow)
        debugAllowOverFullScreen = try c.decode(.debugAllowOverFullScreen, default: d.debugAllowOverFullScreen)
    }

    public static let scaleRange = 0.5...1.5

    /// The model for the selected AI provider.
    public var aiModel: String {
        get { aiModels[aiProvider.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? aiProvider.defaultModel }
        set { aiModels[aiProvider.rawValue] = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public static let defaultMeetingApps = [
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.cisco.webexmeetingsapp",
        "com.webex.meetingmanager", "com.apple.FaceTime", "com.skype.skype",
    ]
    public static let defaultPresentationApps = ["com.apple.iWork.Keynote", "com.microsoft.Powerpoint"]
    public static let defaultReadingApps = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.apple.Preview", "com.adobe.Reader", "com.apple.iBooksX", "com.readdle.PDFExpert-Mac", "net.shinyfrog.bear",
    ]
    /// Browsers: a meeting in a browser tab is recognised by window title.
    public static let browserApps = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac", "company.thebrowser.Browser"]
    public static let togetherRange = 2...3
}

/// Which loaded pets may appear, from the pet settings.
public enum PetRoster {
    /// Pets enabled by the user (order preserved).
    public static func enabled(_ ids: [String], settings: AppSettings) -> [String] {
        ids.filter { !settings.disabledPets.contains($0) }
    }

    /// Pets eligible for an automatic appearance. In single mode, the chosen pet (or the first enabled one if the
    /// choice is missing or disabled).
    public static func active(_ ids: [String], settings: AppSettings) -> [String] {
        let on = enabled(ids, settings: settings)
        switch settings.petMode {
        case .mix: return on
        case .single:
            if let id = settings.singlePetID, on.contains(id) { return [id] }
            return Array(on.prefix(1))
        }
    }

    /// How many pets this appearance brings: 1, or 2…maxTogether when the "together" roll succeeds.
    public static func groupSize(available: Int, settings: AppSettings, rng: RandomSource) -> Int {
        guard settings.petMode == .mix, available >= 2, rng.chance(settings.togetherChance) else { return 1 }
        let maxN = min(available, max(AppSettings.togetherRange.lowerBound, min(settings.maxTogether, AppSettings.togetherRange.upperBound)))
        return rng.int(in: 2...maxN)
    }
}
