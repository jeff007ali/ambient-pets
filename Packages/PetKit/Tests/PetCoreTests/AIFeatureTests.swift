import Foundation
import Testing
@testable import PetCore

@Suite struct RoutineComposerTests {
    let lib = RoutineLibrary(
        enter: [StepDefinition(clip: "idle", duration: 1)],
        exit: [StepDefinition(clip: "idle", duration: 1)],
        blocks: [
            "shot": RoutineBlock(description: "fires", steps: [StepDefinition(clip: "shoot", duration: 1)]),
            "hop": RoutineBlock(description: "hops", steps: [StepDefinition(clip: "idle", duration: 0.8)]),
            "long": RoutineBlock(description: "long", steps: [StepDefinition(clip: "idle", duration: 12)]),
        ])

    @Test func composesEnterBlocksExitWithASpeechSlot() throws {
        let s = try #require(RoutineComposer.compose(lib, petID: "iron", blocks: ["iron.shot", "hop", "nope"]))
        #expect(s.steps.map(\.clip) == ["idle", "shoot", "idle", "idle"])
        #expect(s.steps[1].speech?.chance == 0.6)
        #expect(PackValidator.sceneDurationRange.contains(s.totalDuration))
        #expect(s.tags.contains("ai"))
    }

    @Test func needsTwoUsableBlocks() {
        #expect(RoutineComposer.compose(lib, petID: "iron", blocks: ["shot"]) == nil)
        #expect(RoutineComposer.compose(lib, petID: "iron", blocks: ["x", "y"]) == nil)
    }

    @Test func dropsBlocksThatWouldExceedTheLimitAndCapsCount() throws {
        let s = try #require(RoutineComposer.compose(lib, petID: "iron", blocks: ["long", "long", "long", "shot", "hop", "hop", "hop"]))
        #expect(s.totalDuration <= PackValidator.sceneDurationRange.upperBound)
        #expect(s.steps.count <= 2 + RoutineComposer.maxBlocks)
    }

    @Test func realBlockFilesCompose() throws {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { dir.deleteLastPathComponent() }
        for pet in ["ironman", "spiderman", "batman"] {
            let url = dir.appending(path: "Pets/\(pet)/blocks.json")
            guard let data = FileManager.default.contents(atPath: url.path) else { continue }
            let lib = try JSONDecoder().decode(RoutineLibrary.self, from: data)
            let names = RoutineComposer.qualifiedNames(lib, petID: pet)
            #expect(names.count >= 5)
            let s = RoutineComposer.compose(lib, petID: pet, blocks: Array(names.prefix(4)))
            #expect(s != nil, "\(pet)")
        }
    }
}

@Suite struct MoodTests {
    @Test func moodsShiftPersonalityWithinBounds() {
        var p = Personality()
        p.friendliness = 0.9
        let cheerful = Mood.cheerful.apply(to: p)
        #expect(cheerful.friendliness == 1)
        #expect(Mood.sleepy.apply(to: Personality()).activity == 0.6)
        #expect(Mood.brooding.apply(to: Personality()).friendliness == 0.2)
    }

    @Test func bookExpiresAtMidnight() {
        let today = date(2026, 10, 12, 9), tomorrow = date(2026, 10, 13, 9)
        let book = MoodBook(day: MoodBook.dayKey(today, calendar: newYork), moods: ["iron": .playful])
        #expect(book.current(on: today, calendar: newYork) == ["iron": .playful])
        #expect(book.current(on: tomorrow, calendar: newYork).isEmpty)
        #expect(!book.needsMoods(on: today, pets: ["iron"], calendar: newYork))
        #expect(book.needsMoods(on: today, pets: ["iron", "bat"], calendar: newYork))
        #expect(book.needsMoods(on: tomorrow, pets: ["iron"], calendar: newYork))
    }
}

@Suite struct AIExtendedChoiceTests {
    func openAI(_ inner: String) -> Data {
        let root: JSONValue = .object(["choices": .array([.object(["finish_reason": .string("stop"),
            "message": .object(["content": .string(inner), "refusal": .null])])])])
        return try! JSONEncoder().encode(root)
    }

    @Test func routineAndMoodsAreValidated() throws {
        let c = try #require(AIChooser.parseOpenAIResponse(
            openAI(#"{"scene":"routine:iron","speech":"","routine":["iron.shot","bogus","iron.hop"],"moods":{"iron":"playful","bat":"angry"}}"#),
            candidates: ["routine:iron"], blocks: ["iron.shot", "iron.hop"], moodPets: ["iron", "bat"]))
        #expect(c.routine == ["iron.shot", "iron.hop"])
        #expect(c.moods == ["iron": .playful]) // "angry" isn't a mood
    }

    @Test func routineIgnoredForNonRoutineKeys() throws {
        let c = try #require(AIChooser.parseOpenAIResponse(openAI(#"{"scene":"a/b","speech":"","routine":["iron.shot"]}"#),
                                                         candidates: ["a/b"], blocks: ["iron.shot"]))
        #expect(c.routine.isEmpty)
    }

    @Test func schemaAddsMoodsOnlyWhenAsked() throws {
        let without = String(decoding: try JSONEncoder().encode(AIChooser.schema(keys: ["a/b"])), as: UTF8.self)
        #expect(!without.contains("moods"))
        #expect(without.contains(#""routine""#))
        let with = String(decoding: try JSONEncoder().encode(AIChooser.schema(keys: ["a/b"], blocks: ["x.y"], moodPets: ["iron"])), as: UTF8.self)
        #expect(with.contains("moods") && with.contains("playful") && with.contains("x.y"))
    }

    @Test func summaryCarriesGeneralStatsOnly() throws {
        let s = AIContextSummary(state: .activeWork, appCategory: "developer-tools", date: date(2026, 10, 12, 15), recentScenes: [],
                                 focusMinutes: 95, appearancesToday: 4, moods: ["Batman": "brooding"], calendar: newYork)
        #expect(s.weekday == "Monday" && s.timeOfDay == "afternoon")
        let text = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
        #expect(text.contains("focusMinutes") && text.contains("brooding"))
    }

    @Test func candidateKindsHaveStableKeys() {
        #expect(AICandidate.interaction(id: "greeting", name: "Greeting", pets: ["a", "b"], tier: .funny).key == "interaction:greeting")
        #expect(AICandidate.together(pets: ["a", "b"]).key == "together")
        #expect(AICandidate.routine(petID: "iron", petName: "Iron Man", personality: Personality()).key == "routine:iron")
    }
}
