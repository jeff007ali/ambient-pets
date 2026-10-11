import CoreGraphics
import Foundation
import Testing
@testable import PetCore

@Suite struct SpriteSlicerTests {
    static let magenta = RGBA(r: 255, g: 0, b: 255)
    static let red = RGBA(r: 200, g: 20, b: 20)

    /// 40×20 sheet on a magenta background:
    /// - A: 5×5 block at (2, 2)
    /// - B: 4×4 block at (20, 3) plus a detached 2×2 "effect" at (25, 3), 1 px away → merged
    /// - a single noise pixel at (35, 15) → dropped
    func sheet() -> RGBAImage {
        var img = RGBAImage(width: 40, height: 20)
        for y in 0..<20 { for x in 0..<40 { img.set(x, y, Self.magenta) } }
        func fill(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int) {
            for y in y0..<(y0 + h) { for x in x0..<(x0 + w) { img.set(x, y, Self.red) } }
        }
        fill(2, 2, 5, 5)
        fill(20, 3, 4, 4)
        fill(25, 3, 2, 2)
        fill(35, 15, 1, 1)
        return img
    }

    @Test func detectsBackgroundFromCorner() {
        #expect(SpriteSlicer.detectBackground(sheet()) == Self.magenta)
        #expect(SpriteSlicer.detectBackground(RGBAImage(width: 2, height: 2)) == nil)
    }

    @Test func slicesMergesAndDropsNoise() {
        var img = sheet()
        var options = SpriteSlicer.Options()
        options.minPixels = 4
        let (bg, frames) = SpriteSlicer.slice(&img, options: options)
        #expect(bg == Self.magenta)
        #expect(frames.map(\.rect) == [
            PixelRect(x: 2, y: 2, width: 5, height: 5),
            PixelRect(x: 20, y: 3, width: 7, height: 4),
        ])
        #expect(frames.map(\.index) == [0, 1])
        #expect(frames[1].pixelCount == 20)
        #expect(img.alpha(0, 0) == 0) // keyed out
    }

    @Test func pivotIsBottomCentreOfOpaquePixels() {
        var img = sheet()
        _ = SpriteSlicer.slice(&img)
        #expect(SpriteSlicer.autoPivot(img, in: PixelRect(x: 2, y: 2, width: 5, height: 5)) == [2, 5])
    }

    @Test func readingOrderIsRowsThenColumns() {
        let r = SpriteSlicer.readingOrder([
            PixelRect(x: 50, y: 0, width: 10, height: 30),
            PixelRect(x: 0, y: 40, width: 10, height: 10),
            PixelRect(x: 0, y: 5, width: 10, height: 10), // same row as the first (starts above its bottom)
        ])
        #expect(r.map(\.x) == [0, 50, 0])
        #expect(r.map(\.y) == [5, 0, 40])
    }

    @Test func gapMath() {
        let a = PixelRect(x: 0, y: 0, width: 10, height: 10)
        #expect(a.gap(to: PixelRect(x: 10, y: 0, width: 5, height: 5)) == 0) // touching
        #expect(a.gap(to: PixelRect(x: 13, y: 0, width: 5, height: 5)) == 3)
        #expect(a.gap(to: PixelRect(x: 12, y: 14, width: 5, height: 5)) == 4)
    }

    @Test func hexColours() {
        #expect(RGBA(hex: "#FF00ff") == Self.magenta)
        #expect(RGBA(hex: "nope") == nil)
        #expect(Self.magenta.hex == "#FF00FF")
    }
}

@Suite struct PackValidatorTests {
    func pack(clips: [String: ClipDefinition], scenes: [SceneDefinition], lines: [String: [String]] = [:]) throws -> PetPackData {
        let def = try decode(PetDefinition.self, #"{"id": "t", "capabilities": {"canFly": true}}"#)
        let atlas = SpriteAtlas(image: "sheet.png", frames: [
            "i0": AtlasFrame(rect: CGRect(x: 0, y: 0, width: 10, height: 10), pivot: CGPoint(x: 5, y: 10)),
        ])
        return PetPackData(directory: URL(fileURLWithPath: "/nonexistent"), definition: def, atlas: atlas,
                           clips: ClipLibrary(clips), scenes: scenes, lines: lines)
    }

    @Test func validPackHasNoErrors() throws {
        var s = scene("ok", .quick)
        s.steps[0].speech = SpeechSpec(pool: "hi", text: nil, chance: 1)
        let p = try pack(clips: ["idle": ClipDefinition(frames: ["i0"]), "look": ClipDefinition(frames: nil, fallback: "idle")],
                         scenes: [s], lines: ["hi": ["Hello."]])
        let issues = PackValidator.validate(p, imageSize: CGSize(width: 64, height: 64))
        #expect(issues.filter { $0.severity == .error }.isEmpty, "\(issues)")
    }

    @Test func reportsEveryProblem() throws {
        var bad = StepDefinition(clip: "missing", motion: MotionSpec(type: "teleport", to: "moon"), duration: 1,
                                 effects: [EffectSpec("confetti")])
        bad.sound = "boom"
        bad.speech = SpeechSpec(pool: "nope", text: nil, chance: 1)
        var s = SceneDefinition(id: "bad", tier: .quick, allowedContexts: ["SPACE"], steps: [bad])
        s.requires = SceneRequirements(capabilities: ["canSwing"])
        let p = try pack(clips: ["idle": ClipDefinition(frames: ["i0", "ghost"]),
                                 "a": ClipDefinition(frames: nil, fallback: "b"), "b": ClipDefinition(frames: nil, fallback: "a")],
                         scenes: [s, s])
        let messages = PackValidator.validate(p, imageSize: CGSize(width: 64, height: 64)).map(\.description)
        let expected = [
            "unknown frame 'ghost'", "fallback cycle", "duplicate scene id", "lasts 1.0s", "unknown context 'SPACE'",
            "capability 'canSwing'", "clip 'missing' is not defined", "unknown motion 'teleport'", "unknown anchor 'moon'",
            "unknown effect 'confetti'", "unknown sound 'boom'", "speech pool 'nope'",
        ]
        for e in expected {
            #expect(messages.contains { $0.contains(e) }, "missing: \(e)\n\(messages.joined(separator: "\n"))")
        }
    }

    @Test func frameOutsideImageIsAnError() throws {
        let p = try pack(clips: ["idle": ClipDefinition(frames: ["i0"])], scenes: [scene("ok", .quick)])
        let issues = PackValidator.validate(p, imageSize: CGSize(width: 8, height: 8))
        #expect(issues.contains { $0.message.contains("outside") })
    }
}

@Suite struct TorsoPivotTests {
    @Test func torsoPivotFollowsTheBodyNotTheFeet() {
        // 20×20 figure: body column at x 8…11 (rows 0…13), one foot sticking far right on the bottom rows.
        var img = RGBAImage(width: 20, height: 20)
        let c = RGBA(r: 200, g: 0, b: 0)
        for y in 0..<14 { for x in 8..<12 { img.set(x, y, c) } }
        for y in 14..<20 { for x in 14..<19 { img.set(x, y, c) } }
        let rect = PixelRect(x: 0, y: 0, width: 20, height: 20)
        #expect(SpriteSlicer.autoPivot(img, in: rect) == [16, 20])
        #expect(SpriteSlicer.torsoPivot(img, in: rect) == [9, 20])
    }
}
