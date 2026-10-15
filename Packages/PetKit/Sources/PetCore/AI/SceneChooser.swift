import Foundation

/// What an AI chooser may see (plan §M8): coarse context only. Window titles are included only when the user
/// explicitly allows it; app identity is reduced to a category. Activity stats are general (minutes, counts).
public struct AIContextSummary: Codable, Sendable, Hashable {
    public var state: String
    public var appCategory: String?
    public var timeOfDay: String
    /// Local time, "HH:mm".
    public var localTime: String
    public var weekday: String
    public var recentScenes: [String]
    public var windowTitle: String?
    /// Minutes of continuous activity without a break (≥ 5 min away), when working or reading.
    public var focusMinutes: Int?
    /// Minutes away from the keyboard right now, when idle.
    public var awayMinutes: Int?
    public var appearancesToday: Int
    /// Today's pet moods (pet name → mood), once assigned.
    public var moods: [String: String]
    /// The pets' last few AI lines (to avoid repeating them).
    public var recentLines: [String]

    public init(state: ContextState, appCategory: String?, date: Date, recentScenes: [String], windowTitle: String? = nil,
                focusMinutes: Int? = nil, awayMinutes: Int? = nil, appearancesToday: Int = 0, recentLines: [String] = [],
                moods: [String: String] = [:], calendar: Calendar = .current) {
        self.state = state.rawValue
        self.appCategory = appCategory
        let h = calendar.component(.hour, from: date)
        timeOfDay = switch h {
        case 5..<12: "morning"
        case 12..<17: "afternoon"
        case 17..<22: "evening"
        default: "night"
        }
        localTime = String(format: "%02d:%02d", h, calendar.component(.minute, from: date))
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        weekday = names[(calendar.component(.weekday, from: date) - 1 + 7) % 7]
        self.recentScenes = recentScenes
        self.windowTitle = windowTitle
        self.focusMinutes = focusMinutes
        self.awayMinutes = awayMinutes
        self.appearancesToday = appearancesToday
        self.moods = moods
        self.recentLines = recentLines
    }
}

/// One option offered to the AI.
/// - `scene`: key "pet/scene" — play that scene.
/// - `interaction`: key "interaction:<id>" — a shared scene for several pets.
/// - `together`: key "together" — several pets at once, each with its own scene.
/// - `routine`: key "routine:<pet>" — compose a new short routine from that pet's blocks.
public struct AICandidate: Codable, Sendable, Hashable {
    public var key: String
    public var kind: String
    public var pet: String?
    public var pets: [String]?
    public var scene: String?
    public var tier: String?
    public var tags: [String]?
    public var personality: Personality?

    public init(_ c: SceneCandidate, petName: String, personality: Personality) {
        key = c.key
        kind = "scene"
        pet = petName
        scene = c.scene.name
        tier = c.scene.tier.rawValue
        tags = c.scene.tags
        self.personality = personality
    }

    public static func interaction(id: String, name: String, pets: [String], tier: SceneTier) -> AICandidate {
        AICandidate(key: "interaction:\(id)", kind: "interaction", pets: pets, scene: name, tier: tier.rawValue)
    }

    public static func together(pets: [String]) -> AICandidate {
        AICandidate(key: "together", kind: "together", pets: pets, scene: "several pets at once, separate scenes")
    }

    public static func routine(petID: String, petName: String, personality: Personality) -> AICandidate {
        AICandidate(key: "routine:\(petID)", kind: "routine", pet: petName, scene: "compose a new routine from this pet's blocks",
                    personality: personality)
    }

    init(key: String, kind: String, pet: String? = nil, pets: [String]? = nil, scene: String? = nil, tier: String? = nil,
         tags: [String]? = nil, personality: Personality? = nil) {
        self.key = key
        self.kind = kind
        self.pet = pet
        self.pets = pets
        self.scene = scene
        self.tier = tier
        self.tags = tags
        self.personality = personality
    }
}

/// Which service answers the AI chooser.
public enum AIProvider: String, Codable, Sendable, CaseIterable, Hashable {
    case openai, anthropic

    public var displayName: String { self == .openai ? "OpenAI" : "Anthropic (Claude)" }
    public var defaultModel: String { self == .openai ? "gpt-6-luna" : "claude-haiku-5-5" }
    /// Presets offered in Settings (any other id can be typed in).
    public var suggestedModels: [String] {
        self == .openai ? ["gpt-6-luna", "gpt-5.6-luna", "gpt-5.4-mini", "gpt-4.1-mini"]
                        : ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]
    }
}

/// Everything the AI may be asked in one call.
public struct AIRequest: Sendable, Hashable {
    public var summary: AIContextSummary
    public var candidates: [AICandidate]
    /// Routine building blocks: qualified name ("ironman.repulsor_shot") → description.
    public var blocks: [String: String]
    /// Pet ids that still need today's mood (empty: don't ask).
    public var moodPets: [String]

    public init(summary: AIContextSummary, candidates: [AICandidate], blocks: [String: String] = [:], moodPets: [String] = []) {
        self.summary = summary
        self.candidates = candidates
        self.blocks = blocks
        self.moodPets = moodPets
    }
}

public struct AIChoice: Sendable, Hashable {
    public var key: String
    public var speech: String?
    /// Block names for a `routine:` choice, validated against the offered blocks.
    public var routine: [String]
    /// Today's moods, when they were asked for.
    public var moods: [String: Mood]

    public init(key: String, speech: String?, routine: [String] = [], moods: [String: Mood] = [:]) {
        self.key = key
        self.speech = speech
        self.routine = routine
        self.moods = moods
    }
}

/// Prompt, output schema and response validation for the opt-in AI chooser. The AI only ever picks from the
/// already-filtered candidates (every gate has run before it is asked) and its answer is validated again here.
public enum AIChooser {
    /// A bubble is read at a glance: about six words.
    public static let maxSpeechLength = 40

    public static let system = """
    You direct short cameos of animated desktop pets that appear briefly on a user's Mac screen. Pick exactly one \
    key from the candidates. Prefer variety (avoid the recent scenes) and fit the user's context, time of day and \
    the pets' personalities and moods. Candidate kinds: "scene" plays an authored scene; "interaction" is a shared \
    scene for several pets; "together" brings several pets at once; "routine" means you compose a new short routine \
    for that pet: then fill "routine" with 2 to 5 of that pet's block names in a fun order (otherwise leave it empty). \
    Speech: write one very short, friendly, in-character line (at most 6 words and 40 characters, no emoji; it \
    shows in a small speech bubble for a few seconds, so it must be readable at a glance) that reacts to the \
    user's situation right now, so it feels aware of them: the local time or weekday (a late night, a Monday \
    morning, Friday afternoon), what they're doing (state: working, reading, idle, and the app category), a long \
    focus streak (nudge a stretch, water or a break), coming back after being away, how many cameos today, or the \
    pet's mood. Speak as that pet. Don't repeat recentLines. Never mention specific apps, window titles, names or \
    content. Leave speech empty only if nothing fits. If "moods" is \
    requested, give each listed pet a mood for today that suits its character, with some variety.
    """

    public static func userMessage(summary: AIContextSummary, candidates: [AICandidate]) -> String {
        userMessage(AIRequest(summary: summary, candidates: candidates))
    }

    public static func userMessage(_ r: AIRequest) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        func json<T: Encodable>(_ v: T) -> String { (try? String(data: enc.encode(v), encoding: .utf8)) ?? "null" }
        var text = "Context: \(json(r.summary))\nCandidates: \(json(r.candidates))"
        if !r.blocks.isEmpty { text += "\nRoutine blocks: \(json(r.blocks))" }
        if !r.moodPets.isEmpty { text += "\nAssign today's moods for: \(json(r.moodPets)) (choices: \(json(Mood.allCases.map(\.rawValue))))" }
        return text
    }

    /// JSON schema for structured output: `scene` must be one of the candidates; `routine` items must be offered
    /// blocks; `moods` (only when asked) has one entry per listed pet. All properties required (OpenAI strict mode).
    public static func schema(keys: [String], blocks: [String] = [], moodPets: [String] = []) -> JSONValue {
        let routineItems: JSONValue = blocks.isEmpty ? .object(["type": .string("string")])
            : .object(["type": .string("string"), "enum": .array(blocks.sorted().map { .string($0) })])
        var properties: [String: JSONValue] = [
            "scene": .object(["type": .string("string"), "enum": .array(keys.map { .string($0) })]),
            "speech": .object(["type": .string("string")]),
            "routine": .object(["type": .string("array"), "items": routineItems]),
        ]
        var required: [JSONValue] = [.string("scene"), .string("speech"), .string("routine")]
        if !moodPets.isEmpty {
            let moodEnum: JSONValue = .object(["type": .string("string"), "enum": .array(Mood.allCases.map { .string($0.rawValue) })])
            properties["moods"] = .object([
                "type": .string("object"),
                "properties": .object(Dictionary(uniqueKeysWithValues: moodPets.map { ($0, moodEnum) })),
                "required": .array(moodPets.map { .string($0) }),
                "additionalProperties": .bool(false),
            ])
            required.append(.string("moods"))
        }
        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required),
            "additionalProperties": .bool(false),
        ])
    }

    /// Messages API request body (raw HTTP; no Swift SDK exists).
    public static func requestBody(model: String, summary: AIContextSummary, candidates: [AICandidate]) -> JSONValue {
        requestBody(model: model, AIRequest(summary: summary, candidates: candidates))
    }

    public static func requestBody(model: String, _ r: AIRequest) -> JSONValue {
        .object([
            "model": .string(model),
            "max_tokens": .number(1024),
            "system": .string(system),
            "messages": .array([.object(["role": .string("user"), "content": .string(userMessage(r))])]),
            "output_config": .object([
                // Low effort keeps the answer well inside the 2 s budget.
                "effort": .string("low"),
                "format": .object(["type": .string("json_schema"),
                                   "schema": schema(keys: r.candidates.map(\.key), blocks: Array(r.blocks.keys), moodPets: r.moodPets)]),
            ]),
        ])
    }

    /// The structured answer → a validated choice (shared by both providers).
    static func choice(fromJSONText text: String, candidates: Set<String>, blocks: Set<String>, moodPets: [String]) -> AIChoice? {
        guard let inner = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), case .object(let o) = inner,
              let key = o["scene"]?.string, candidates.contains(key) else { return nil }
        let routine = (o["routine"]?.array ?? []).compactMap(\.string).filter { blocks.contains($0) }
        var moods: [String: Mood] = [:]
        if case .object(let m)? = o["moods"] {
            for pet in moodPets { if let v = m[pet]?.string, let mood = Mood(rawValue: v) { moods[pet] = mood } }
        }
        return AIChoice(key: key, speech: o["speech"]?.string.flatMap(sanitize),
                        routine: key.hasPrefix("routine:") ? Array(routine.prefix(RoutineComposer.maxBlocks)) : [], moods: moods)
    }

    /// OpenAI Chat Completions request body: strict JSON-schema structured output (every property required,
    /// no extra properties), low reasoning effort on reasoning models to stay inside the 2 s budget.
    public static func openAIRequestBody(model: String, summary: AIContextSummary, candidates: [AICandidate]) -> JSONValue {
        openAIRequestBody(model: model, AIRequest(summary: summary, candidates: candidates))
    }

    public static func openAIRequestBody(model: String, _ r: AIRequest) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(model),
            "max_completion_tokens": .number(1024),
            "messages": .array([
                .object(["role": .string("system"), "content": .string(system)]),
                .object(["role": .string("user"), "content": .string(userMessage(r))]),
            ]),
            "response_format": .object([
                "type": .string("json_schema"),
                "json_schema": .object([
                    "name": .string("scene_choice"),
                    "strict": .bool(true),
                    "schema": schema(keys: r.candidates.map(\.key), blocks: Array(r.blocks.keys), moodPets: r.moodPets),
                ]),
            ]),
        ]
        if isOpenAIReasoningModel(model) { body["reasoning_effort"] = .string("low") }
        return .object(body)
    }

    /// GPT-5+ and o-series models take `reasoning_effort`; older chat models (gpt-4.x) reject it.
    public static func isOpenAIReasoningModel(_ model: String) -> Bool {
        let m = model.lowercased()
        if m.hasPrefix("o1") || m.hasPrefix("o3") || m.hasPrefix("o4") { return true }
        guard m.hasPrefix("gpt-"), let major = Int(m.dropFirst(4).prefix { $0.isNumber }) else { return false }
        return major >= 5
    }

    /// Validates an OpenAI Chat Completions response. nil for refusals, truncation, non-JSON or unknown keys.
    public static func parseOpenAIResponse(_ data: Data, candidates: Set<String>, blocks: Set<String> = [], moodPets: [String] = []) -> AIChoice? {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let msg) = root,
              let first = msg["choices"]?.array?.first, case .object(let entry) = first,
              entry["finish_reason"]?.string == "stop",
              case .object(let message)? = entry["message"] else { return nil }
        if let refusal = message["refusal"]?.string, !refusal.isEmpty { return nil }
        guard let text = message["content"]?.string else { return nil }
        return choice(fromJSONText: text, candidates: candidates, blocks: blocks, moodPets: moodPets)
    }

    /// Validates a Messages API response body. Returns nil (→ rule chooser) for refusals, truncation, non-JSON,
    /// or a key that isn't one of the candidates.
    public static func parseResponse(_ data: Data, candidates: Set<String>, blocks: Set<String> = [], moodPets: [String] = []) -> AIChoice? {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let msg) = root else { return nil }
        guard msg["stop_reason"]?.string == "end_turn" else { return nil }
        guard let content = msg["content"]?.array else { return nil }
        for block in content {
            guard case .object(let b) = block, b["type"]?.string == "text", let text = b["text"]?.string else { continue }
            return choice(fromJSONText: text, candidates: candidates, blocks: blocks, moodPets: moodPets)
        }
        return nil
    }

    static let blocked = ["fuck", "shit", "bitch", "cunt", "dick", "bastard", "asshole", "slut", "whore", "nigg", "fag", "retard", "kill yourself", "kys"]

    /// Single line, length-capped, no blocked words; empty → nil.
    public static func sanitize(_ s: String) -> String? {
        var t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        t = String(t.unicodeScalars.filter { !$0.properties.isEmoji || $0.isASCII }).trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let lower = t.lowercased()
        if blocked.contains(where: { lower.contains($0) }) { return nil }
        guard t.count > maxSpeechLength else { return t }
        // Too long: the first sentence if it fits, else cut at a word boundary.
        if let end = t.firstIndex(where: { ".!?".contains($0) }), t.distance(from: t.startIndex, to: end) < maxSpeechLength {
            return String(t[...end])
        }
        let head = String(t.prefix(maxSpeechLength - 1))
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "…"
    }
}
