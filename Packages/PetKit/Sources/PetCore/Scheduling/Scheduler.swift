import Foundation

public enum GateReason: String, Sendable, Hashable {
    case disabled, paused, quietHours, locked, dailyLimit, contextPaused, underLoad, busy

    public var label: String {
        switch self {
        case .disabled: "Pets disabled"
        case .paused: "Paused"
        case .quietHours: "Quiet hours"
        case .locked: "Screen locked"
        case .dailyLimit: "Daily limit reached"
        case .contextPaused: "Paused for current activity"
        case .underLoad: "Machine under load"
        case .busy: "A scene is playing"
        }
    }
}

public enum GateResult: Sendable, Hashable {
    case open
    /// `retryAt == nil`: don't retry on a timer; an event (settings change, unlock) will reschedule.
    case blocked(GateReason, retryAt: Date?)
}

/// Everything the gates look at, gathered at fire time.
public struct GateInputs: Sendable {
    public var now: Date
    public var settings: AppSettings
    public var pausedUntil: Date?
    public var isLocked: Bool
    public var appearancesToday: Int
    public var policy: ContextPolicy
    public var underLoad: Bool
    public var scenePlaying: Bool

    public init(now: Date, settings: AppSettings, pausedUntil: Date? = nil, isLocked: Bool = false,
                appearancesToday: Int = 0, policy: ContextPolicy, underLoad: Bool = false, scenePlaying: Bool = false) {
        self.now = now
        self.settings = settings
        self.pausedUntil = pausedUntil
        self.isLocked = isLocked
        self.appearancesToday = appearancesToday
        self.policy = policy
        self.underLoad = underLoad
        self.scenePlaying = scenePlaying
    }
}

/// Decides *when* pets appear (spec §8.2, plan §4.5). Pure; the engine owns the actual timer.
public struct Scheduler: Sendable {
    public var calendar: Calendar
    /// Retry window when a gate is closed with no known end time.
    public var backoffRange: ClosedRange<Double> = 60...120
    /// Never schedule closer than this.
    public var minimumDelay: Double = 20

    public init(calendar: Calendar = .current) { self.calendar = calendar }

    /// Gate order: enabled → pause → quiet hours → lock → daily limit → context policy → load → busy.
    public func evaluateGates(_ g: GateInputs, rng: RandomSource) -> GateResult {
        let jitter = { rng.double(in: 15...90) }
        if !g.settings.enabled { return .blocked(.disabled, retryAt: nil) }
        if let until = g.pausedUntil, until > g.now { return .blocked(.paused, retryAt: until + jitter()) }
        if g.settings.quietHours.contains(g.now, calendar: calendar) {
            let end = g.settings.quietHours.end(after: g.now, calendar: calendar) ?? g.now + backoff(rng)
            return .blocked(.quietHours, retryAt: end + jitter())
        }
        if g.isLocked { return .blocked(.locked, retryAt: nil) }
        if g.settings.dailyLimit > 0, g.appearancesToday >= g.settings.dailyLimit {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: g.now)) ?? g.now + 86_400
            return .blocked(.dailyLimit, retryAt: tomorrow + jitter())
        }
        if g.policy.paused { return .blocked(.contextPaused, retryAt: g.now + backoff(rng)) }
        if g.underLoad && g.settings.skipUnderLoad { return .blocked(.underLoad, retryAt: g.now + backoff(rng) * 2) }
        if g.scenePlaying { return .blocked(.busy, retryAt: g.now + backoff(rng)) }
        return .open
    }

    public func backoff(_ rng: RandomSource) -> Double { rng.double(in: backoffRange) }

    /// Seconds until the next appearance:
    /// `uniform(min, max) ÷ (contextMultiplier × activity)`, never before `lastAppearance + cooldown`.
    public func nextDelay(settings: AppSettings, policy: ContextPolicy, activity: Double = 1,
                          lastAppearance: Date?, now: Date, rng: RandomSource) -> Double {
        let lo = max(min(settings.minIntervalMinutes, settings.maxIntervalMinutes), 0.1) * 60
        let hi = max(max(settings.minIntervalMinutes, settings.maxIntervalMinutes), 0.1) * 60
        let base = rng.double(in: lo...hi)
        let frequency = max(policy.frequencyMultiplier * activity, 0.05)
        var delay = base / frequency
        if let last = lastAppearance {
            let cooldownEnd = last.addingTimeInterval(settings.cooldownMinutes * 60)
            delay = max(delay, cooldownEnd.timeIntervalSince(now))
        }
        return max(delay, minimumDelay)
    }
}
