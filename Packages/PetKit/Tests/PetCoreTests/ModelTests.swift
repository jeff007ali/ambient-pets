import CoreGraphics
import Foundation
import Testing
@testable import PetCore

func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

@Suite struct DecodingTests {
    @Test func effectDecodesFromStringOrObject() throws {
        let fx = try decode([EffectSpec].self, #"["thruster", {"type": "beam", "length": 140, "at": [10, 20]}]"#)
        #expect(fx[0].type == .thruster)
        #expect(fx[0].params.isEmpty)
        #expect(fx[1].type == .beam)
        #expect(fx[1].double("length") == 140)
        #expect(fx[1].point("at") == CGPoint(x: 10, y: 20))
    }

    @Test func effectWithoutTypeFails() {
        #expect(throws: DecodingError.self) { try decode(EffectSpec.self, #"{"length": 3}"#) }
    }

    @Test func sceneDefaultsAndUnknownFieldsAreTolerated() throws {
        let s = try decode(SceneDefinition.self, #"""
        { "id": "x", "futureField": {"a": 1},
          "steps": [ { "clip": "idle", "duration": 3, "alsoNew": true } ] }
        """#)
        #expect(s.tier == .quick)
        #expect(s.weight == 1)
        #expect(s.region == .bottomEdge)
        #expect(s.steps[0].motion == .none)
        #expect(s.steps[0].effects.isEmpty)
        #expect(s.totalDuration == 3)
    }

    @Test func unknownMotionTypeDecodes() throws {
        let m = try decode(MotionSpec.self, #"{"type": "teleport"}"#)
        #expect(m.type.rawValue == "teleport")
        #expect(!MotionType.supported.contains(m.type))
    }

    @Test func petDefaults() throws {
        let p = try decode(PetDefinition.self, #"{"id": "cat"}"#)
        #expect(p.name == "cat")
        #expect(p.formatVersion == 1)
        #expect(p.renderer == "sprite")
        #expect(p.personality.activity == 1)
        #expect(!p.has("canFly"))
    }

    @Test func settingsDecodeFromPartialJSON() throws {
        let s = try decode(AppSettings.self, #"{"maxFPS": 24, "quietHours": {"enabled": true, "startMinutes": 60, "endMinutes": 120}}"#)
        #expect(s.maxFPS == 24)
        #expect(s.quietHours.enabled)
        #expect(s.enabled) // default
        #expect(s.petScale == 0.8)
    }

    @Test func settingsRoundTrip() throws {
        var s = AppSettings()
        s.enabledTiers = [.quick]
        s.petScale = 1.2
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}

@Suite struct AtlasTests {
    @Test func explicitFramesDefaultPivotToBottomCentre() throws {
        let a = try decode(SpriteAtlas.self, #"{"image": "s.png", "frames": {"a": {"rect": [0,0,10,20]}, "b": {"rect": [10,0,8,8], "pivot": [1,2]}}}"#)
        let f = a.resolvedFrames(imageWidth: 100, imageHeight: 100)
        #expect(f["a"]?.pivot == CGPoint(x: 5, y: 20))
        #expect(f["b"]?.pivot == CGPoint(x: 1, y: 2))
        #expect(a.facing == .right)
    }

    @Test func gridFramesAreGenerated() throws {
        let a = try decode(SpriteAtlas.self, #"{"image": "s.png", "grid": {"frameSize": [32, 32], "names": ["walk_0", "walk_1"]}}"#)
        let f = a.resolvedFrames(imageWidth: 96, imageHeight: 32)
        #expect(f.count == 3)
        #expect(f["walk_1"]?.rect == CGRect(x: 32, y: 0, width: 32, height: 32))
        #expect(f["2"] != nil)
    }

    @Test func extents() {
        let f = ResolvedFrame(rect: CGRect(x: 0, y: 0, width: 40, height: 60), pivot: CGPoint(x: 10, y: 55))
        #expect(f.extents == SpriteExtents(left: 10, right: 30, up: 55, down: 5))
    }
}

@Suite struct ClipLibraryTests {
    let lib = ClipLibrary([
        "idle": ClipDefinition(frames: ["i0", "i1"], fps: 2),
        "look": ClipDefinition(frames: nil, fallback: "idle"),
        "hud_scan": ClipDefinition(frames: [], fallback: "look"),
        "a": ClipDefinition(frames: nil, fallback: "b"),
        "b": ClipDefinition(frames: nil, fallback: "a"),
        "once": ClipDefinition(frames: ["o0", "o1", "o2"], fps: 10, loop: false),
    ])

    @Test func fallbackChainResolves() throws {
        let c = try lib.resolve("hud_scan").get()
        #expect(c.sourceID == "idle")
        #expect(c.requestedID == "hud_scan")
    }

    @Test func cycleIsDetected() {
        #expect(lib.resolve("a") == .failure(.cycle(["a", "b", "a"])))
    }

    @Test func missingFallsBackToIdleByDefault() {
        #expect(lib.resolveOrDefault("nope")?.sourceID == "idle")
    }

    @Test func frameTiming() throws {
        let idle = try lib.resolve("idle").get()
        #expect(idle.frameName(at: 0) == "i0")
        #expect(idle.frameName(at: 0.5) == "i1")
        #expect(idle.frameName(at: 1.0) == "i0") // loops
        let once = try lib.resolve("once").get()
        #expect(once.frameName(at: 10) == "o2") // holds last frame
    }
}

extension Result where Success == ResolvedClip, Failure == ClipResolutionError {
    static func == (l: Self, r: Self) -> Bool {
        switch (l, r) {
        case (.success(let a), .success(let b)): a == b
        case (.failure(let a), .failure(let b)): a == b
        default: false
        }
    }
}

struct SpeechAndTimingRuleTests {
    @Test func petsTalkOnlyWhenStill() {
        #expect(StepDefinition(clip: "idle", duration: 1).isStill)
        #expect(StepDefinition(clip: "idle", motion: MotionSpec(type: .hover), duration: 1).isStill)
        #expect(StepDefinition(clip: "cling", motion: MotionSpec(type: .cling, to: "current"), duration: 1).isStill)
        #expect(!StepDefinition(clip: "walk", motion: MotionSpec(type: .exit, to: "side_offscreen"), duration: 1).isStill)
        let glide = SceneDefinition(id: "g", tier: .quick, steps: [StepDefinition(clip: "glide", motion: MotionSpec(type: .arc), duration: 4)])
        #expect(!glide.canSpeak)
    }

    @Test func flagsAStepThatOutlastsItsAnimation() {
        var punch = ClipDefinition(frames: ["a", "b", "c"], fps: 10, loop: false)
        let lib = ClipLibrary(["punch": punch, "pose": ClipDefinition(frames: ["p"], fps: 1, loop: false)])
        #expect(abs((PackValidator.frozenTail(StepDefinition(clip: "punch", duration: 0.45), clips: lib) ?? 0) - 0.15) < 1e-9)
        #expect(PackValidator.frozenTail(StepDefinition(clip: "punch", duration: 0.3), clips: lib) == nil)
        // A single-frame pose is meant to be held; so is a looping clip.
        #expect(PackValidator.frozenTail(StepDefinition(clip: "pose", duration: 2), clips: lib) == nil)
        punch.loop = true
        #expect(PackValidator.frozenTail(StepDefinition(clip: "punch", duration: 2), clips: ClipLibrary(["punch": punch])) == nil)
    }
}
