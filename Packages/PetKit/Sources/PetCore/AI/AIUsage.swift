import Foundation

/// How much the AI has been used (persisted by the app), shown in Settings ▸ AI and the menu.
public struct AIUsage: Codable, Sendable, Hashable {
    public struct Tally: Codable, Sendable, Hashable {
        /// Requests sent to the provider (scheduled cameos, Summon Now and the Test button).
        public var calls = 0
        /// Calls that came back with a valid pick.
        public var answered = 0
        /// Calls that failed (timeout, network, HTTP error, invalid answer); the normal picker ran instead.
        public var failed = 0
        /// Cameos where the AI wasn't asked because the situation hadn't changed (no request, no cost).
        public var skipped = 0
        /// Tokens as reported by the provider.
        public var inputTokens = 0
        public var outputTokens = 0
        public init() {}
    }

    public struct Entry: Codable, Sendable, Hashable {
        public var date: Date
        public var summary: String
    }

    public static let recentLimit = 20

    /// Day of `today` ("yyyy-MM-dd").
    public var day = ""
    public var today = Tally()
    public var total = Tally()
    /// Newest first.
    public var recent: [Entry] = []

    public init() {}

    /// Starts a new `today` tally when the day changes.
    public mutating func rollOver(to now: Date, calendar: Calendar = .current) {
        let key = MoodBook.dayKey(now, calendar: calendar)
        if key != day {
            day = key
            today = Tally()
        }
    }

    public mutating func recordCall(answered: Bool, inputTokens: Int, outputTokens: Int, summary: String,
                                    at now: Date, calendar: Calendar = .current) {
        rollOver(to: now, calendar: calendar)
        for t in [\AIUsage.today, \AIUsage.total] {
            self[keyPath: t].calls += 1
            if answered { self[keyPath: t].answered += 1 } else { self[keyPath: t].failed += 1 }
            self[keyPath: t].inputTokens += inputTokens
            self[keyPath: t].outputTokens += outputTokens
        }
        recent.insert(Entry(date: now, summary: summary), at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
    }

    public mutating func recordSkip(at now: Date, calendar: Calendar = .current) {
        rollOver(to: now, calendar: calendar)
        today.skipped += 1
        total.skipped += 1
    }
}
