import CoreGraphics
import Foundation
import Testing
@testable import PetCore

@Suite struct EnsembleTests {
    func role(_ id: String, _ pos: HorizontalSideName, requires: [String] = [], waits: [String?] = [nil, nil]) -> EnsembleRole {
        var steps = waits.map { w -> StepDefinition in
            var s = StepDefinition(clip: "idle", duration: 2)
            s.waitFor = w
            return s
        }
        if steps.isEmpty { steps = [StepDefinition(clip: "idle", duration: 3)] }
        return EnsembleRole(id: id, requires: requires, position: pos, steps: steps)
    }

    let flyer = SelectablePet(id: "iron", capabilities: ["canFly": true], scenes: [])
    let climber = SelectablePet(id: "spidey", capabilities: ["canClimb": true], scenes: [])

    @Test func assignmentsRespectCapabilitiesAndUseEachPetOnce() {
        let e = EnsembleScene(id: "x", roles: [role("a", .left, requires: ["canFly"]), role("b", .right)])
        let a = e.assignments(for: [flyer, climber])
        #expect(a == [["a": "iron", "b": "spidey"]])
        #expect(EnsembleScene(id: "y", roles: [role("a", .left), role("b", .right)]).assignments(for: [flyer, climber]).count == 2)
        #expect(e.assignments(for: [climber]).isEmpty)
    }

    @Test func placementPutsRolesEitherSideOfTheMeetingPointWithoutOverlap() {
        let e = EnsembleScene(id: "x", roles: [role("a", .left), role("b", .right)])
        let box = PetBox.make(extents: SpriteExtents(left: 30, right: 30, up: 100, down: 0), scale: 1, padding: .init(side: 20, top: 20, bottom: 40))
        for seed in 0..<30 {
            let p = EnsemblePlanner.place(e, display: primary, boxes: ["a": box, "b": box], rng: SeededRandom(seed: UInt64(seed)))
            let a = p["a"]!.anchor, b = p["b"]!.anchor
            #expect(a.x < b.x)
            #expect(b.x - a.x >= 60) // sprites (30 + 30) don't overlap
            #expect(a.y == primary.visibleFrame.minY && b.y == a.y)
            #expect(p["a"]!.side == .left && p["b"]!.side == .right)
        }
    }

    @Test func waitParsing() {
        #expect(EnsemblePlanner.parseWait("b:2")! == ("b", 2))
        #expect(EnsemblePlanner.parseWait("b:end")!.step == Int.max)
        #expect(EnsemblePlanner.parseWait("nope") == nil)
    }

    @Test func validationCatchesBadWaitsAndUnplayableClips() throws {
        let pet = PetPackData(directory: URL(fileURLWithPath: "/x"), definition: try decode(PetDefinition.self, #"{"id": "p"}"#),
                              atlas: SpriteAtlas(image: "s.png", frames: [:]), clips: ClipLibrary(["idle": ClipDefinition(frames: ["i"])]),
                              scenes: [], lines: [:])
        var b = role("b", .right, waits: ["a:9", "c:1"])
        b.steps.append(StepDefinition(clip: "moonwalk", duration: 1))
        let e = EnsembleScene(id: "bad", roles: [role("a", .left), b])
        let msgs = PackValidator.validate(e, pets: [pet]).map(\.message)
        #expect(msgs.contains { $0.contains("waitFor 'a:9' but role 'a' has 2 steps") })
        #expect(msgs.contains { $0.contains("bad waitFor 'c:1'") })
        #expect(msgs.contains { $0.contains("clip 'moonwalk' is not defined") })
        #expect(PackValidator.validate(EnsembleScene(id: "solo", roles: [role("a", .left)]), pets: [pet]).contains { $0.message.contains("two roles") })
    }

    @Test func petWeightsScaleSelection() {
        var s = AppSettings()
        s.petWeights = ["p": 2.5]
        let pack = PetPackData(directory: URL(fileURLWithPath: "/x"), definition: try! decode(PetDefinition.self, #"{"id": "p", "weight": 2}"#),
                               atlas: SpriteAtlas(image: "s.png", frames: [:]), clips: ClipLibrary([:]), scenes: [], lines: [:])
        #expect(SelectablePet(pack, settings: s).weight == 5)
        #expect(SelectablePet(pack).weight == 2)
    }
}
