import Foundation

public struct AppearanceEvent: Codable, Sendable, Hashable {
    public var date: Date
    public var petID: String
    public var sceneID: String
    public var tier: SceneTier
    public var displayID: UInt32?
    public var context: ContextState?

    public init(date: Date, petID: String, sceneID: String, tier: SceneTier, displayID: UInt32? = nil, context: ContextState? = nil) {
        self.date = date
        self.petID = petID
        self.sceneID = sceneID
        self.tier = tier
        self.displayID = displayID
        self.context = context
    }

    public var key: String { EventHistory.key(pet: petID, scene: sceneID) }
}

/// Lightweight local history (spec §33): recent events plus uncapped per-scene last-played times and counts.
public struct EventHistory: Codable, Sendable, Hashable {
    public static let cap = 200

    public private(set) var events: [AppearanceEvent] = []
    /// "pet/scene" → last time played. Kept beyond the event cap so long cooldowns (rare scenes) still work.
    public private(set) var lastPlayed: [String: Date] = [:]
    public private(set) var sceneCounts: [String: Int] = [:]

    public init() {}

    public static func key(pet: String, scene: String) -> String { "\(pet)/\(scene)" }

    public mutating func record(_ event: AppearanceEvent) {
        events.append(event)
        if events.count > Self.cap { events.removeFirst(events.count - Self.cap) }
        lastPlayed[event.key] = event.date
        sceneCounts[event.key, default: 0] += 1
    }

    public var lastEvent: AppearanceEvent? { events.last }
    public var lastAppearance: Date? { events.last?.date }

    public func lastPlayed(pet: String, scene: String) -> Date? { lastPlayed[Self.key(pet: pet, scene: scene)] }

    /// Keys of the most recent `n` events, newest first.
    public func recentKeys(_ n: Int) -> [String] { events.suffix(n).reversed().map(\.key) }

    public func count(onSameDayAs date: Date, calendar: Calendar = .current) -> Int {
        events.reduce(0) { $0 + (calendar.isDate($1.date, inSameDayAs: date) ? 1 : 0) }
    }
}

/// JSON persistence for `EventHistory`.
public struct HistoryStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// `~/Library/Application Support/AmbientPets/history.json`
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: "AmbientPets").appending(path: "history.json")
    }

    /// A missing or unreadable file yields an empty history (never crashes the app).
    public func load() -> EventHistory {
        guard let data = FileManager.default.contents(atPath: url.path) else { return EventHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(EventHistory.self, from: data)) ?? EventHistory()
    }

    public func save(_ history: EventHistory) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(history).write(to: url, options: .atomic)
    }
}
