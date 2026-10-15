import AppKit
import Observation
import PetCore

/// Orchestrator: owns the one scheduling timer, evaluates gates at fire time, picks pets, scenes and a display, and
/// runs them. An appearance is one pet, or several pets at once (each in its own screen lane). Between appearances
/// the app is idle: no window, no display link, one timer.
@MainActor
@Observable
public final class PetEngine {
    public let settingsStore: SettingsStore
    public private(set) var packs: [LoadedPack] = []
    /// Shared scenes for two or more pets.
    public private(set) var ensembles: [EnsembleScene] = []
    public private(set) var loadFailures: [String] = []
    public private(set) var nextAppearance: Date?
    /// Why the last fire didn't play anything.
    public private(set) var lastGate: GateReason?
    public private(set) var contextState: ContextState = .activeWork
    /// "Pet: Scene" for every scene playing now.
    public private(set) var currentScenes: [String] = []
    public private(set) var pausedUntil: Date?
    public private(set) var appearancesToday = 0
    /// Why the context is what it is (e.g. "microphone in use"), for the menu and Settings.
    public private(set) var contextReason: String?
    /// Last AI chooser call: latency and result, for Settings.
    public private(set) var lastAIResult: String?
    /// How much the AI has been used (persisted): Settings ▸ AI and the menu show it.
    public private(set) var aiUsage = UserDefaults.standard.data(forKey: "aiUsage.v1")
        .flatMap { try? JSONDecoder().decode(AIUsage.self, from: $0) } ?? AIUsage()

    /// Today's tally (rolled over if the day changed since the last call).
    public var aiUsageToday: AIUsage.Tally {
        var u = aiUsage
        u.rollOver(to: clock.now)
        return u.today
    }

    private func saveAIUsage() {
        if let data = try? JSONEncoder().encode(aiUsage) { UserDefaults.standard.set(data, forKey: "aiUsage.v1") }
    }

    /// Counts one AI request (nothing is counted when none was sent, e.g. no key) and logs it at notice level, so
    /// `log show` keeps a history.
    private func recordAICall(_ o: AIClient.Outcome, source: String) {
        let what: String
        if let c = o.choice {
            what = c.key + (c.routine.isEmpty ? "" : " [\(c.routine.joined(separator: ", "))]") + (c.speech.map { " — “\($0)”" } ?? "")
        } else {
            what = "fell back: \(o.error ?? "unknown")"
        }
        let summary = "\(source): \(what) (\(String(format: "%.1f", o.latency)) s, \(o.inputTokens + o.outputTokens) tokens)"
        log.notice("AI call \(summary, privacy: .public)")
        guard o.sent else { return }
        aiUsage.recordCall(answered: o.choice != nil, inputTokens: o.inputTokens, outputTokens: o.outputTokens,
                           summary: summary, at: clock.now)
        saveAIUsage()
    }

    public func resetAIUsage() {
        aiUsage = AIUsage()
        saveAIUsage()
    }

    /// The situation the AI last reacted to. It's asked again only when that changes (see `shouldAskAI`).
    @ObservationIgnored private var lastAISituation: String?
    @ObservationIgnored private var wasAway = false
    /// The user is back after 5+ minutes away (until the AI has reacted to it).
    @ObservationIgnored private var cameBack = false

    /// What the AI's line would be about: activity, part of the day, weekday, each 45 minutes of focus, coming back.
    private func situation(state: ContextState) -> String {
        let focus = state == .activeWork || state == .reading ? Int(clock.now.timeIntervalSince(focusStart) / 60) / 45 : -1
        let s = AIContextSummary(state: state, appCategory: nil, date: clock.now, recentScenes: [])
        return "\(state.rawValue)|\(s.timeOfDay)|\(s.weekday)|focus\(focus)\(cameBack ? "|back" : "")"
    }

    /// The AI is asked once per situation (and when today's moods are due); other cameos use the normal picker and
    /// the pets' own lines, so it isn't called, or talking about the same thing, every time.
    private func shouldAskAI(state: ContextState) -> Bool {
        if settings.aiMoods, moodBook.needsMoods(on: clock.now, pets: activePacks.map(\.id)) { return true }
        if situation(state: state) != lastAISituation { return true }
        lastAIResult = "not asked: same situation as its last line (pets use their own lines until it changes)"
        aiUsage.recordSkip(at: clock.now)
        saveAIUsage()
        return false
    }

    /// The AI's last few lines, so it doesn't repeat itself.
    @ObservationIgnored private var recentAILines: [String] = []
    /// Today's AI-assigned moods (persisted for the day).
    public private(set) var moodBook = (UserDefaults.standard.data(forKey: "moods.v1")).flatMap { try? JSONDecoder().decode(MoodBook.self, from: $0) } ?? MoodBook()
    /// Debug overlay of context, obstacles and planner candidates (not persisted).
    public var showDebugOverlay = false {
        didSet { showDebugOverlay ? startOverlay() : stopOverlay() }
    }

    @ObservationIgnored public let screens = ScreenManager()
    @ObservationIgnored let signals = SystemSignals()
    @ObservationIgnored let context = ContextMonitor()
    @ObservationIgnored private var lastSnapshot: ContextMonitor.Snapshot?
    /// Start of the current focus streak (reset by a break of 5+ minutes away from the keyboard).
    @ObservationIgnored private var focusStart = Date()
    @ObservationIgnored private let audio = AudioPlayer()
    @ObservationIgnored private let overlay = DebugOverlay()
    @ObservationIgnored private var overlayTimer: Timer?
    @ObservationIgnored private let petDirectories: [URL]
    @ObservationIgnored private let historyStore: HistoryStore
    @ObservationIgnored private var history: EventHistory
    @ObservationIgnored private let scheduler = Scheduler()
    @ObservationIgnored private let selector = SceneSelector()
    @ObservationIgnored private let rng: RandomSource = SystemRandom()
    @ObservationIgnored private let clock: PetClock = SystemClock()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var directors: [SceneDirector] = []
    /// Whether the running appearance came from the scheduler (reschedule when it ends) or a manual summon.
    @ObservationIgnored private var scheduledAppearance = false
    @ObservationIgnored private let staticPresenter = StaticPetPresenter()
    @ObservationIgnored private var started = false

    public var settings: AppSettings { settingsStore.settings }
    public var isPaused: Bool { (pausedUntil ?? .distantPast) > clock.now }
    public var historyURL: URL { historyStore.url }
    public var isPlaying: Bool { !currentScenes.isEmpty }
    public var currentScene: String? { currentScenes.isEmpty ? nil : currentScenes.joined(separator: " + ") }

    /// Pets the user has enabled, in load order.
    public var enabledPacks: [LoadedPack] {
        let on = Set(PetRoster.enabled(packs.map(\.id), settings: settings))
        return packs.filter { on.contains($0.id) }
    }

    /// Pets eligible for automatic appearances (honours Mix / Only one).
    public var activePacks: [LoadedPack] {
        let on = Set(PetRoster.active(packs.map(\.id), settings: settings))
        return packs.filter { on.contains($0.id) }
    }

    public init(petDirectories: [URL] = PetDirectories.all(), historyStore: HistoryStore = HistoryStore(url: HistoryStore.defaultURL),
                settingsStore: SettingsStore = SettingsStore()) {
        self.petDirectories = petDirectories
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        history = historyStore.load()
        pausedUntil = UserDefaults.standard.object(forKey: "pausedUntil") as? Date
    }

    public func start() {
        guard !started else { return }
        started = true
        reloadPacks()
        settingsStore.onChange = { [weak self] old, new in self?.settingsChanged(from: old, to: new) }
        screens.onChange = { [weak self] in self?.screensChanged() }
        signals.onChange = { [weak self] event in self?.systemEvent(event) }
        refreshCounters()
        knownDisplays = Set(screens.displays.map(\.id))
        scheduleNext()
    }

    public func reloadPacks() {
        let result = PetDirectories.loadAll(from: petDirectories)
        packs = result.packs
        loadFailures = result.failures
        var loaded: [EnsembleScene] = []
        var seen = Set<String>()
        for dir in PetDirectories.ensembleDirectories(from: petDirectories) {
            let r = EnsembleLoader.load(from: dir)
            loadFailures += r.failures.map { "_ensembles/\($0)" }
            for e in r.ensembles where seen.insert(e.id).inserted {
                let errors = PackValidator.validate(e, pets: packs.map(\.data)).filter { $0.severity == .error }
                if errors.isEmpty { loaded.append(e) } else { loadFailures.append("_ensembles/\(e.id): \(errors.map(\.message).joined(separator: "; "))") }
            }
        }
        ensembles = loaded
        log.info("loaded \(result.packs.count) pack(s): \(result.packs.map(\.id).joined(separator: ", "), privacy: .public)")
    }

    // MARK: - Pet settings

    public func isEnabled(_ petID: String) -> Bool { !settings.disabledPets.contains(petID) }

    public func setEnabled(_ petID: String, _ on: Bool) {
        if on { settingsStore.settings.disabledPets.remove(petID) } else { settingsStore.settings.disabledPets.insert(petID) }
    }

    // MARK: - Manual controls (menu)

    private var anyContext: SelectionContext {
        SelectionContext(state: .idle, policy: PolicyTable.defaultPolicy(for: .idle), enabledTiers: settings.enabledTiers,
                         displayCount: screens.displays.count, now: clock.now)
    }

    /// Plays a random scene by one active pet now, ignoring frequency gates and context. With the AI on, it picks
    /// (and speaks) as it would for a scheduled cameo.
    public func summonRandom() {
        let pool = activePacks.isEmpty ? packs : activePacks
        let (state, policy) = currentPolicy()
        if settings.aiEnabled, AIKeychain.hasKey(settings.aiProvider), !isPlaying, shouldAskAI(state: state) {
            let ctx = SelectionContext(state: state == .idle || policy.paused ? .idle : state,
                                       policy: policy.paused ? PolicyTable.defaultPolicy(for: .idle) : policy,
                                       enabledTiers: settings.enabledTiers, displayCount: screens.displays.count, now: clock.now)
            chooseWithAI(pool: pool, context: ctx, state: state, size: 1, manual: true)
            return
        }
        summonByRules(pool)
    }

    private func summonByRules(_ pool: [LoadedPack]) {
        guard let pick = selector.select(pets: pool.map { self.selectable($0) }, context: anyContext, history: history, rng: rng)
            ?? firstScene(of: pool) else { return }
        play([pick], on: screens.displayUnderMouse, record: false)
    }

    /// Plays scenes by several enabled pets at the same time (up to the "together" setting, at least 2).
    public func summonTogether() {
        let count = max(2, min(settings.maxTogether, AppSettings.togetherRange.upperBound))
        let picks = pickGroup(from: enabledPacks.isEmpty ? packs : enabledPacks, count: count, context: anyContext)
        guard !picks.isEmpty else { return }
        play(picks, on: screens.displayUnderMouse, record: false)
    }

    /// Plays a shared scene with enabled pets that fit its roles.
    public func summonEnsemble(_ id: String) {
        guard !isPlaying, let e = ensembles.first(where: { $0.id == id }) else { return }
        let pool = (enabledPacks.isEmpty ? packs : enabledPacks).map { self.selectable($0) }
        guard let assignment = rng.element(of: e.assignments(for: pool)) else { return }
        playEnsemble(e, assignment: assignment, on: screens.displayUnderMouse, record: false)
    }

    /// Ensembles some enabled pets can play (for the menu).
    public var playableEnsembles: [EnsembleScene] {
        let pool = (enabledPacks.isEmpty ? packs : enabledPacks).map { self.selectable($0) }
        return ensembles.filter { !$0.assignments(for: pool).isEmpty }
    }

    public func summon(petID: String, sceneID: String) {
        guard let scene = packs.first(where: { $0.id == petID })?.scene(sceneID) else { return }
        play([SceneSelection(petID: petID, sceneID: sceneID, tier: scene.tier)], on: screens.displayUnderMouse, record: false)
    }

    /// M1 check: a static pet at the bottom-right of the display under the mouse for 5 s.
    public func summonStatic() {
        guard let display = screens.displayUnderMouse else { return }
        let pack = activePacks.first ?? packs.first
        staticPresenter.show(pack: pack, on: display, scale: pack?.data.definition.renderScale(userScale: settings.petScale) ?? settings.petScale,
                             outline: settings.debugOutlineWindow)
    }

    public func pause(for seconds: TimeInterval) { setPaused(until: clock.now + seconds) }

    public func pauseUntilTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: clock.now))!
        setPaused(until: cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow)
    }

    public func resume() { setPaused(until: nil) }

    /// Dev / debugging: one context snapshot as text.
    public func contextProbe() -> String {
        let (state, policy) = currentPolicy()
        let s = lastSnapshot?.signals ?? ContextSignals()
        var lines = ["state: \(state.rawValue)\(contextReason.map { " (\($0))" } ?? "")",
                     "policy: paused=\(policy.paused) frequency×\(policy.frequencyMultiplier) tiers=\(policy.allowedTiers.map(\.rawValue).sorted())",
                     "frontmost: \(s.frontmostBundleID ?? "-") fullScreen=\(s.frontmostIsFullScreen) game=\(s.isGaming) presenting=\(s.isPresenting) reading=\(s.frontmostIsReadingApp)",
                     "meeting: \(s.meetingReason ?? "no")",
                     "idle: \(Int(s.idleSeconds)) s, since keystroke: \(Int(s.secondsSinceKeystroke)) s, locked=\(s.isLocked)",
                     "permissions: accessibility=\(ContextMonitor.hasAccessibility) screenRecording=\(ContextMonitor.hasScreenRecording)"]
        for o in lastSnapshot?.obstacles ?? [] { lines.append("obstacle \(o.kind.rawValue): \(o.rect.integral)") }
        return lines.joined(separator: "\n")
    }

    /// Re-reads the context (Settings → Context "Refresh").
    public func refreshContext() { _ = currentPolicy() }

    /// Debug: run the scheduler's fire path now (gates included).
    public func fireNow() { fire() }

    private func setPaused(until date: Date?) {
        pausedUntil = date
        UserDefaults.standard.set(date, forKey: "pausedUntil")
        if date != nil { abortAll("paused") }
        scheduleNext()
    }

    private func abortAll(_ reason: String) {
        for d in directors { d.abort(reason) }
    }

    // MARK: - Picking

    private func firstScene(of pool: [LoadedPack]) -> SceneSelection? {
        pool.first.flatMap { p in p.data.scenes.first.map { SceneSelection(petID: p.id, sceneID: $0.id, tier: $0.tier) } }
    }

    /// One scene each for up to `count` different pets. The first pet is picked by the selector's weights; the
    /// others are picked from the remaining pets the same way.
    private func pickGroup(from pool: [LoadedPack], count: Int, context: SelectionContext) -> [SceneSelection] {
        var remaining = pool.map { self.selectable($0) }
        var picks: [SceneSelection] = []
        while picks.count < count, !remaining.isEmpty,
              let pick = selector.select(pets: remaining, context: context, history: history, rng: rng) {
            picks.append(pick)
            remaining.removeAll { $0.id == pick.petID }
        }
        return picks
    }

    // MARK: - AI appearances

    /// Pet as the selector sees it, with today's mood applied to its personality.
    private func selectable(_ pack: LoadedPack) -> SelectablePet {
        var p = SelectablePet(pack.data, settings: settings)
        if let mood = todaysMoods[pack.id] { p.personality = mood.apply(to: p.personality) }
        return p
    }

    /// Today's moods (empty until the AI assigns them; reset every day).
    public var todaysMoods: [String: Mood] { moodBook.current(on: clock.now) }

    private func storeMoods(_ moods: [String: Mood]) {
        guard !moods.isEmpty else { return }
        var current = moodBook.current(on: clock.now)
        current.merge(moods) { _, new in new }
        moodBook = MoodBook(day: MoodBook.dayKey(clock.now), moods: current)
        if let data = try? JSONEncoder().encode(moodBook) { UserDefaults.standard.set(data, forKey: "moods.v1") }
    }

    /// General activity stats for the AI (no app names, no content).
    private func aiSummary(state: ContextState) -> AIContextSummary {
        let now = clock.now
        let idle = lastSnapshot?.signals.idleSeconds ?? 0
        let names = Dictionary(packs.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return AIContextSummary(
            state: state, appCategory: AIClient.frontmostCategory(), date: now, recentScenes: history.recentKeys(5),
            windowTitle: settings.aiShareWindowTitles ? AIClient.frontmostWindowTitle() : nil,
            focusMinutes: state == .activeWork || state == .reading ? Int(now.timeIntervalSince(focusStart) / 60) : nil,
            awayMinutes: state == .idle ? Int(idle / 60) : nil,
            appearancesToday: appearancesToday, recentLines: recentAILines,
            moods: Dictionary(todaysMoods.map { (names[$0.key] ?? $0.key, $0.value.rawValue) }, uniquingKeysWith: { a, _ in a }))
    }

    /// The options and request for one AI appearance of `size` pets.
    private func aiRequest(pool: [LoadedPack], context: SelectionContext, state: ContextState, size: Int)
        -> (AIRequest, singles: [SceneCandidate], interactions: [String: (EnsembleScene, [[String: String]])]) {
        let names = Dictionary(pool.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var candidates: [AICandidate] = []
        var singles: [SceneCandidate] = []
        var interactions: [String: (EnsembleScene, [[String: String]])] = [:]
        var blocks: [String: String] = [:]
        if size >= 2 {
            if settings.aiInteractions {
                for (e, assignments) in eligibleEnsembles(from: pool, maxPets: size, context: context) {
                    let c = AICandidate.interaction(id: e.id, name: e.name,
                                                    pets: Array(Set(assignments.flatMap(\.values))).sorted().map { names[$0] ?? $0 }, tier: e.tier)
                    candidates.append(c)
                    interactions[c.key] = (e, assignments)
                }
            }
            candidates.append(.together(pets: pool.map(\.name)))
        } else {
            singles = selector.eligible(pets: pool.map(selectable), context: context, history: history)
            for c in singles {
                let pet = pool.first { $0.id == c.petID }
                candidates.append(AICandidate(c, petName: names[c.petID] ?? c.petID,
                                              personality: pet.map { selectable($0).personality } ?? Personality()))
            }
            if settings.aiRoutines {
                for p in pool {
                    guard let lib = p.data.routines else { continue }
                    candidates.append(.routine(petID: p.id, petName: p.name, personality: selectable(p).personality))
                    for (name, block) in lib.blocks { blocks["\(p.id).\(name)"] = block.description }
                }
            }
        }
        let moodPets = settings.aiMoods && moodBook.needsMoods(on: clock.now, pets: pool.map(\.id)) ? pool.map(\.id) : []
        return (AIRequest(summary: aiSummary(state: state), candidates: candidates, blocks: blocks, moodPets: moodPets), singles, interactions)
    }

    /// Opt-in AI appearance (every gate has passed): one call picks a scene, an interaction, a together appearance
    /// or composes a routine, and may set today's moods and a speech line. Any failure → the rule appearance.
    /// `manual`: a menu summon (no gates, not counted, plays under the pointer).
    private func chooseWithAI(pool: [LoadedPack], context: SelectionContext, state: ContextState, size: Int, manual: Bool = false) {
        let (request, singles, interactions) = aiRequest(pool: pool, context: context, state: state, size: size)
        let fallback = { [weak self] (size: Int) in
            guard let self else { return }
            if manual { self.summonByRules(pool) } else { self.ruleAppearance(pool: pool, context: context, state: state, size: size) }
        }
        guard request.candidates.count >= 2 else { fallback(size); return }
        let provider = settings.aiProvider, model = settings.aiModel
        Task { @MainActor [weak self] in
            let outcome = await AIClient.choose(provider: provider, model: model, request: request)
            guard let self else { return }
            self.lastAIResult = outcome.choice.map { c in
                "picked \(c.key)\(c.routine.isEmpty ? "" : " [\(c.routine.joined(separator: ", "))]") in \(String(format: "%.2f", outcome.latency)) s"
            } ?? "fell back (\(outcome.error ?? "unknown")) after \(String(format: "%.2f", outcome.latency)) s"
            self.recordAICall(outcome, source: manual ? "Summon Now" : "cameo")
            if let moods = outcome.choice?.moods { self.storeMoods(moods) }
            if outcome.choice != nil {
                // This situation has had its AI moment; generic lines until it changes.
                self.lastAISituation = self.situation(state: state)
                self.cameBack = false
            }
            if let line = outcome.choice?.speech { self.recentAILines = Array((self.recentAILines + [line]).suffix(6)) }
            // Things may have changed during the call: never play past a pause, lock or disable.
            if manual {
                guard !self.isPlaying, !self.signals.isLocked else { return }
            } else {
                guard self.settings.enabled, !self.isPaused, !self.signals.isLocked, !self.isPlaying else { self.scheduleNext(); return }
            }
            guard let choice = outcome.choice else { fallback(size); return }
            let display = manual ? self.screens.displayUnderMouse : self.screens.randomDisplay(self.rng)
            let speech = self.settings.aiSpeech ? choice.speech : nil
            let record = !manual
            let obstacles = self.lastSnapshot?.obstacles
            if choice.key == "together" {
                let picks = self.pickGroup(from: pool, count: size, context: context)
                if picks.isEmpty { fallback(1) }
                else { self.play(picks, on: display, record: record, context: state, obstacles: obstacles, speech: speech) }
            } else if let (e, assignments) = interactions[choice.key], let assignment = self.rng.element(of: assignments) {
                self.playEnsemble(e, assignment: assignment, on: display, record: record, context: state)
            } else if choice.key.hasPrefix("routine:") {
                let petID = String(choice.key.dropFirst("routine:".count))
                guard let pack = pool.first(where: { $0.id == petID }), let lib = pack.data.routines,
                      let scene = RoutineComposer.compose(lib, petID: petID, blocks: choice.routine) else {
                    fallback(1)
                    return
                }
                self.play([SceneSelection(petID: petID, sceneID: scene.id, tier: scene.tier)], on: display, record: record,
                          context: state, obstacles: obstacles, speech: speech, custom: [petID: scene])
            } else if let c = singles.first(where: { $0.key == choice.key }) {
                self.play([SceneSelection(petID: c.petID, sceneID: c.scene.id, tier: c.scene.tier)], on: display,
                          record: record, context: state, obstacles: obstacles, speech: speech)
            } else {
                fallback(size)
            }
        }
    }

    /// The normal (non-AI) appearance: maybe an interaction, else one or more pets with weighted scene picks.
    private func ruleAppearance(pool: [LoadedPack], context ctx: SelectionContext, state: ContextState, size: Int) {
        if size >= 2, rng.chance(settings.interactionChance), let (e, assignment) = pickEnsemble(from: pool, maxPets: size, context: ctx) {
            playEnsemble(e, assignment: assignment, on: screens.randomDisplay(rng), record: true, context: state)
            return
        }
        let picks = pickGroup(from: pool, count: size, context: ctx)
        guard !picks.isEmpty else {
            log.info("no eligible scene for \(state.rawValue, privacy: .public)")
            schedule(at: clock.now + scheduler.backoff(rng))
            return
        }
        play(picks, on: screens.randomDisplay(rng), record: true, context: state, obstacles: lastSnapshot?.obstacles ?? [])
    }

    /// Settings "Test": one AI call with the current context (a single-pet request, routines included). Nothing plays.
    public func testAI() async -> String {
        let (state, policy) = currentPolicy()
        let pool = activePacks.isEmpty ? packs : activePacks
        let ctx = SelectionContext(state: state == .idle || policy.paused ? .idle : state,
                                   policy: policy.paused ? PolicyTable.defaultPolicy(for: .idle) : policy,
                                   enabledTiers: settings.enabledTiers, displayCount: screens.displays.count, now: clock.now)
        let (request, _, _) = aiRequest(pool: pool, context: ctx, state: state, size: 1)
        let o = await AIClient.choose(provider: settings.aiProvider, model: settings.aiModel, request: request)
        recordAICall(o, source: "Test")
        let r = o.choice.map { c in
            var t = "✓ \(c.key)"
            if !c.routine.isEmpty { t += " [\(c.routine.joined(separator: ", "))]" }
            if let sp = c.speech { t += " — “\(sp)”" }
            if !c.moods.isEmpty { t += " · moods: \(c.moods.map { "\($0.key) \($0.value.rawValue)" }.sorted().joined(separator: ", "))" }
            return t + " in \(String(format: "%.2f", o.latency)) s"
        } ?? "✗ \(o.error ?? "failed") after \(String(format: "%.2f", o.latency)) s"
        lastAIResult = r
        return r
    }

    /// Dev: play a composed routine directly (`--summon routine:ironman:repulsor_shot,celebrate`).
    public func summonRoutine(petID: String, blocks: [String]) {
        guard let pack = packs.first(where: { $0.id == petID }), let lib = pack.data.routines,
              let scene = RoutineComposer.compose(lib, petID: petID, blocks: blocks, speechChance: 1) else { return }
        play([SceneSelection(petID: petID, sceneID: scene.id, tier: scene.tier)], on: screens.displayUnderMouse, record: false,
             speech: "Made this one up.", custom: [petID: scene])
    }

    /// An eligible shared scene (tiers, context, cooldown) and a pet-to-role assignment, weighted by scene weight.
    private func pickEnsemble(from pool: [LoadedPack], maxPets: Int, context: SelectionContext) -> (EnsembleScene, [String: String])? {
        let options = eligibleEnsembles(from: pool, maxPets: maxPets, context: context)
        guard let i = rng.weightedIndex(options.map(\.0.weight)), let assignment = rng.element(of: options[i].1) else { return nil }
        return (options[i].0, assignment)
    }

    /// Shared scenes that may play now, with every valid pet-to-role assignment.
    private func eligibleEnsembles(from pool: [LoadedPack], maxPets: Int, context: SelectionContext) -> [(EnsembleScene, [[String: String]])] {
        let pets = pool.map(selectable)
        var options: [(EnsembleScene, [[String: String]])] = []
        for e in ensembles where e.roles.count <= maxPets {
            guard context.enabledTiers.contains(e.tier), context.policy.allowedTiers.contains(e.tier) else { continue }
            if !e.allowedContexts.isEmpty, !e.allowedContexts.contains(context.state.rawValue) { continue }
            let last = pets.compactMap { history.lastPlayed(pet: $0.id, scene: e.id) }.max()
            if let last, context.now.timeIntervalSince(last) < e.cooldownMinutes * 60 { continue }
            let a = e.assignments(for: pets)
            if !a.isEmpty { options.append((e, a)) }
        }
        return options
    }

    /// Runs one director per role, placed around a meeting point, with waits and partner facing wired between them.
    private func playEnsemble(_ e: EnsembleScene, assignment: [String: String], on display: DisplayGeometry?, record: Bool,
                              context: ContextState? = nil) {
        guard !isPlaying, let display else { return }
        var options = SceneDirector.Options()
        options.userScale = settings.petScale
        options.maxFPS = settings.maxFPS
        options.speechBubbles = settings.speechBubbles
        options.reduceQuality = settings.reduceQuality
        options.outlineWindow = settings.debugOutlineWindow
        options.reactToCursor = false // they look at each other, not the pointer

        var boxes: [String: PetBox] = [:]
        var parts: [(EnsembleRole, LoadedPack, SceneDefinition)] = []
        for role in e.roles {
            guard let petID = assignment[role.id], let pack = packs.first(where: { $0.id == petID }) else { return }
            let scene = e.scene(for: role)
            boxes[role.id] = SceneDirector.box(for: scene, pack: pack, scale: pack.data.definition.renderScale(userScale: settings.petScale), display: display)
            parts.append((role, pack, scene))
        }
        let places = EnsemblePlanner.place(e, display: display, boxes: boxes, rng: rng)
        var byRole: [String: SceneDirector] = [:]
        scheduledAppearance = record
        for (role, pack, scene) in parts {
            let label = "\(pack.name): \(e.name)"
            let d = SceneDirector(pack: pack, scene: scene, display: display, options: options, rng: rng,
                                  allDisplays: screens.displays, placement: places[role.id]) { [weak self] outcome in
                self?.directorFinished(label: label, outcome: outcome)
            }
            d.safetyCheck = { [weak self] frame in self?.safetyCheck(frame: frame, scheduled: record) ?? .ok }
            d.playSound = { [weak self] pack, name in self?.playSound(name, pack: pack, scheduled: record) }
            byRole[role.id] = d
            directors.append(d)
            currentScenes.append(label)
            if record {
                history.record(AppearanceEvent(date: clock.now, petID: pack.id, sceneID: e.id, tier: e.tier, displayID: display.id, context: context))
            }
        }
        for (roleID, d) in byRole {
            d.waitGate = { [weak d] spec in
                guard d != nil, let (other, step) = EnsemblePlanner.parseWait(spec), let o = byRole[other] else { return true }
                return (o.hasStarted && !o.isRunning) || o.currentStepNumber >= step
            }
            let partners = byRole.filter { $0.key != roleID }.map(\.value)
            d.partnerPosition = { partners.first?.pivotPosition }
        }
        log.info("playing ensemble \(e.id, privacy: .public) with \(assignment.values.sorted().joined(separator: ", "), privacy: .public)")
        for d in byRole.values { d.start() }
        if record {
            do { try historyStore.save(history) } catch { log.error("history save failed: \(error.localizedDescription, privacy: .public)") }
            refreshCounters()
        }
    }

    // MARK: - Scheduling

    private func takeSnapshot() -> ContextMonitor.Snapshot {
        let snap = context.snapshot(settings: settings, idleSeconds: signals.idleSeconds(), sinceKeystroke: signals.secondsSinceKeystroke(),
                                    locked: signals.isLocked, displays: screens.displays)
        if snap.signals.idleSeconds >= 300 || snap.signals.isLocked {
            focusStart = clock.now
            wasAway = true
        } else if wasAway, snap.signals.idleSeconds < 60 {
            wasAway = false
            cameBack = true
        }
        return snap
    }

    private func currentPolicy() -> (ContextState, ContextPolicy) {
        let snap = takeSnapshot()
        lastSnapshot = snap
        let state = ContextClassifier.classify(snap.signals, idleThreshold: settings.idleThresholdSeconds)
        contextState = state
        contextReason = Self.describe(state, snap.signals)
        return (state, PolicyTable.policy(for: state, settings: settings))
    }

    static func describe(_ state: ContextState, _ s: ContextSignals) -> String? {
        switch state {
        case .videoCall: s.meetingReason
        case .gaming: s.frontmostBundleID.map { "game: \($0)" }
        case .fullScreen, .presentation: s.frontmostBundleID
        case .reading: s.frontmostBundleID.map { "reading in \($0)" }
        case .idle: "no input for \(Int(s.idleSeconds)) s"
        default: nil
        }
    }

    private var averageActivity: Double {
        let pool = activePacks
        guard !pool.isEmpty else { return 1 }
        return pool.map { selectable($0).personality.activity }.reduce(0, +) / Double(pool.count)
    }

    /// Schedules the next fire from the frequency settings (or right after a pause ends).
    private func scheduleNext() {
        guard settings.enabled else { cancelTimer(); lastGate = .disabled; return }
        let now = clock.now
        if let until = pausedUntil, until > now {
            schedule(at: until + rng.double(in: 15...90))
            return
        }
        let (_, policy) = currentPolicy()
        // A paused context still schedules normally; the gate check at fire time backs off.
        let effective = policy.paused ? PolicyTable.defaultPolicy(for: .activeWork) : policy
        let delay = scheduler.nextDelay(settings: settings, policy: effective, activity: averageActivity,
                                        lastAppearance: history.lastAppearance, now: now, rng: rng)
        schedule(at: now + delay)
    }

    private func schedule(at date: Date) {
        cancelTimer()
        nextAppearance = date
        let interval = max(date.timeIntervalSince(clock.now), 1)
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        // Generous tolerance lets macOS coalesce wakeups; a few seconds either way is invisible here.
        t.tolerance = min(interval * 0.1, 30)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
        nextAppearance = nil
    }

    private func fire() {
        cancelTimer()
        let now = clock.now
        refreshCounters()
        let (state, policy) = currentPolicy()
        let inputs = GateInputs(now: now, settings: settings, pausedUntil: pausedUntil, isLocked: signals.isLocked,
                                appearancesToday: appearancesToday, policy: policy, underLoad: signals.underLoad,
                                scenePlaying: isPlaying)
        switch scheduler.evaluateGates(inputs, rng: rng) {
        case .blocked(let reason, let retryAt):
            lastGate = reason
            log.info("gate closed: \(reason.rawValue, privacy: .public)")
            if let retryAt { schedule(at: retryAt) }
        case .open:
            lastGate = nil
            let ctx = SelectionContext(state: state, policy: policy, enabledTiers: settings.enabledTiers,
                                       displayCount: screens.displays.count, now: now)
            let pool = activePacks
            let size = PetRoster.groupSize(available: pool.count, settings: settings, rng: rng)
            if settings.aiEnabled, AIKeychain.hasKey(settings.aiProvider), shouldAskAI(state: state) {
                chooseWithAI(pool: pool, context: ctx, state: state, size: size)
            } else {
                ruleAppearance(pool: pool, context: ctx, state: state, size: size)
            }
        }
    }

    /// Starts one scene per pick on the same display, each in its own lane, slightly staggered.
    private func play(_ picks: [SceneSelection], on display: DisplayGeometry?, record: Bool, context: ContextState? = nil,
                      obstacles: [Obstacle]? = nil, speech: String? = nil, custom: [String: SceneDefinition] = [:]) {
        guard !isPlaying, let display else { return }
        // Manual summons still keep clear of the caret and pointer; scheduled ones use the fire-time snapshot.
        let obstacles = obstacles ?? (settings.avoidUI ? takeSnapshot().obstacles : [])
        var options = SceneDirector.Options()
        options.userScale = settings.petScale
        options.maxFPS = settings.maxFPS
        options.speechBubbles = settings.speechBubbles
        options.reduceQuality = settings.reduceQuality
        options.outlineWindow = settings.debugOutlineWindow
        options.reactToCursor = settings.reactToCursor

        let laneOrder = picks.count > 1 ? Array((0..<picks.count).shuffled()) : [0]
        scheduledAppearance = record
        var started = 0
        for (i, pick) in picks.enumerated() {
            guard let pack = packs.first(where: { $0.id == pick.petID }), let scene = custom[pick.petID] ?? pack.scene(pick.sceneID) else { continue }
            let lane = picks.count > 1 ? ScreenLane(index: laneOrder[i], count: picks.count) : nil
            let label = "\(pack.name): \(scene.name)"
            // One pet says the AI line (the first one to start).
            options.speechOverride = started == 0 ? speech : nil
            let d = SceneDirector(pack: pack, scene: scene, display: display, options: options, rng: rng, lane: lane,
                                  obstacles: obstacles, allDisplays: screens.displays) { [weak self] outcome in
                self?.directorFinished(label: label, outcome: outcome)
            }
            if d.isBlocked {
                log.info("no clear spot for \(pack.id, privacy: .public)/\(scene.id, privacy: .public); skipped")
                continue
            }
            d.safetyCheck = { [weak self] frame in self?.safetyCheck(frame: frame, scheduled: record) ?? .ok }
            d.playSound = { [weak self] pack, name in self?.playSound(name, pack: pack, scheduled: record) }
            if record {
                history.record(AppearanceEvent(date: clock.now, petID: pack.id, sceneID: scene.id, tier: scene.tier,
                                               displayID: display.id, context: context))
            }
            log.info("playing \(pack.id, privacy: .public)/\(scene.id, privacy: .public) on display \(display.id)")
            started += 1
            directors.append(d)
            currentScenes.append(label)
            // A short stagger reads as "and here comes the other one" rather than a synchronised routine.
            if i == 0 {
                d.start()
            } else {
                Task { @MainActor [weak d] in
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 300...1200)))
                    d?.start()
                }
            }
        }
        if record {
            do { try historyStore.save(history) } catch { log.error("history save failed: \(error.localizedDescription, privacy: .public)") }
            refreshCounters()
            if started == 0 { schedule(at: clock.now + scheduler.backoff(rng)) }
        }
    }

    /// Once a second while a scene plays: leave if a meeting / full-screen app / lock starts (scheduled
    /// appearances), and get out of the way if the caret moves under the pet (all appearances).
    private func safetyCheck(frame: CGRect, scheduled: Bool) -> SceneDirector.SafetyAction {
        let snap = takeSnapshot()
        if scheduled {
            let state = ContextClassifier.classify(snap.signals, idleThreshold: settings.idleThresholdSeconds)
            if PolicyTable.policy(for: state, settings: settings).paused, state != .idle {
                contextState = state
                return .abort(state.rawValue)
            }
        }
        if settings.avoidUI, snap.obstacles.contains(where: { $0.kind == .caret && $0.rect.intersects(frame) }) {
            return .exitEarly
        }
        return .ok
    }

    private func playSound(_ name: String, pack: LoadedPack, scheduled: Bool) {
        guard settings.soundsEnabled, !settings.quietHours.contains(clock.now) else { return }
        if scheduled, !PolicyTable.policy(for: contextState, settings: settings).audioAllowed { return }
        audio.play(name, pack: pack, volume: settings.volume)
    }

    // MARK: - Debug overlay

    private func startOverlay() {
        refreshOverlay()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshOverlay() } }
        RunLoop.main.add(t, forMode: .common)
        overlayTimer = t
    }

    private func stopOverlay() {
        overlayTimer?.invalidate()
        overlayTimer = nil
        overlay.hide()
    }

    private func refreshOverlay() {
        let (state, _) = currentPolicy()
        overlay.update(displays: screens.displays, state: state, reason: contextReason, obstacles: lastSnapshot?.obstacles ?? [],
                       candidates: directors.flatMap(\.planCandidates), anchors: directors.map(\.anchor))
    }

    private func directorFinished(label: String, outcome: SceneDirector.Outcome) {
        if case .aborted(let why) = outcome { log.info("scene aborted: \(why, privacy: .public)") }
        directors.removeAll { !$0.isRunning && $0.hasStarted }
        if let i = currentScenes.firstIndex(of: label) { currentScenes.remove(at: i) }
        guard currentScenes.isEmpty else { return }
        directors.removeAll()
        // Nothing on screen: release decoded sprite sheets and sounds until the next appearance.
        for p in packs { p.purgeImages() }
        audio.purge()
        // Manual summons don't disturb an already-scheduled appearance.
        if scheduledAppearance || timer == nil { scheduleNext() }
    }

    private func refreshCounters() {
        appearancesToday = history.count(onSameDayAs: clock.now)
    }

    // MARK: - Events

    private func settingsChanged(from old: AppSettings, to new: AppSettings) {
        let timing = old.enabled != new.enabled || old.minIntervalMinutes != new.minIntervalMinutes
            || old.maxIntervalMinutes != new.maxIntervalMinutes || old.cooldownMinutes != new.cooldownMinutes
            || old.quietHours != new.quietHours || old.dailyLimit != new.dailyLimit
        if !new.enabled { abortAll("disabled") }
        if timing { scheduleNext() }
    }

    @ObservationIgnored private var knownDisplays: Set<UInt32> = []

    /// Hot-plug: a display appearing or disappearing mid-scene ends the scene with a quick fade (a flight may be
    /// heading for a display that no longer exists, or the arrangement may have changed under it).
    private func screensChanged() {
        let now = Set(screens.displays.map(\.id))
        defer { knownDisplays = now }
        guard !knownDisplays.isEmpty, now != knownDisplays else { return }
        abortAll("display configuration changed")
    }

    private func systemEvent(_ event: SystemSignals.Event) {
        switch event {
        case .locked, .willSleep:
            abortAll("\(event)")
        case .unlocked, .didWake:
            focusStart = clock.now
            // Timers drift across sleep; recompute instead of firing a stale one (never sooner than the backoff).
            let soonest = clock.now + scheduler.backoff(rng)
            if let next = nextAppearance, next > soonest { return }
            schedule(at: soonest)
        case .loadChanged:
            if signals.underLoad && settings.skipUnderLoad { abortAll("under load") }
        }
    }
}
