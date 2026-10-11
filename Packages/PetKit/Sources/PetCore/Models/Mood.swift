import Foundation

/// A pet's mood for the day (assigned by the AI chooser): nudges its personality and how often it shows up.
public enum Mood: String, Codable, Sendable, CaseIterable, Hashable {
    case cheerful, playful, mischievous, focused, brooding, sleepy

    public var label: String { rawValue }

    /// Activity multiplier (frequency).
    public var activityFactor: Double {
        switch self {
        case .playful: 1.25
        case .cheerful, .mischievous: 1.1
        case .focused: 0.9
        case .brooding: 0.8
        case .sleepy: 0.6
        }
    }

    public func apply(to p: Personality) -> Personality {
        var p = p
        func bump(_ v: inout Double, _ d: Double) { v = min(max(v + d, 0), 1) }
        switch self {
        case .cheerful: bump(&p.friendliness, 0.3)
        case .playful: bump(&p.mischievousness, 0.2); bump(&p.interaction, 0.2)
        case .mischievous: bump(&p.mischievousness, 0.4)
        case .focused: bump(&p.curiosity, 0.3); bump(&p.mischievousness, -0.2)
        case .brooding: bump(&p.friendliness, -0.3); bump(&p.curiosity, 0.2)
        case .sleepy: bump(&p.interaction, -0.3)
        }
        p.activity *= activityFactor
        return p
    }
}

/// Today's moods, keyed by pet id. A new day starts with none.
public struct MoodBook: Codable, Sendable, Hashable {
    public var day: String
    public var moods: [String: Mood]

    public init(day: String = "", moods: [String: Mood] = [:]) {
        self.day = day
        self.moods = moods
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Moods valid for `date` (empty once the day has changed).
    public func current(on date: Date, calendar: Calendar = .current) -> [String: Mood] {
        day == Self.dayKey(date, calendar: calendar) ? moods : [:]
    }

    public func needsMoods(on date: Date, pets: [String], calendar: Calendar = .current) -> Bool {
        let now = current(on: date, calendar: calendar)
        return pets.contains { now[$0] == nil }
    }
}
