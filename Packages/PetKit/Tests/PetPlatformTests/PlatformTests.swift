import CoreGraphics
import Foundation
import PetCore
import PetImaging
import Testing
@testable import PetPlatform

/// Writes a minimal valid pack (one 8×12 frame) and returns its directory.
func makeFixturePack(id: String, in root: URL, clip: String = "idle", sceneSeconds: Double = 3) throws -> URL {
    let dir = root.appending(path: id)
    try FileManager.default.createDirectory(at: dir.appending(path: "sprites"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dir.appending(path: "scenes"), withIntermediateDirectories: true)
    var img = RGBAImage(width: 8, height: 12)
    for y in 0..<12 { for x in 0..<8 { img.set(x, y, RGBA(r: 200, g: 30, b: 30)) } }
    try ImageFiles.writePNG(img.makeCGImage()!, to: dir.appending(path: "sprites/sheet.png"))
    let files: [String: String] = [
        "pet.json": #"{"formatVersion": 1, "id": "\#(id)", "name": "\#(id)", "height": 12}"#,
        "sprites/atlas.json": #"{"image": "sheet.png", "facing": "right", "frames": {"f0": {"rect": [0, 0, 8, 12], "pivot": [4, 12]}}}"#,
        "clips.json": #"{"clips": {"idle": {"frames": ["f0"]}}}"#,
        "scenes/s.json": #"{"id": "s", "tier": "quick", "steps": [{"clip": "\#(clip)", "duration": \#(sceneSeconds)}]}"#,
    ]
    for (name, text) in files { try Data(text.utf8).write(to: dir.appending(path: name)) }
    return dir
}

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appending(path: "petplatform-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

let testDisplay = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                  visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805), backingScale: 2)

/// The repo's Pets/ directory, if the sheets have been built (`make art`).
var repoPets: URL? {
    var dir = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { dir.deleteLastPathComponent() }
    let pets = dir.appending(path: "Pets")
    return FileManager.default.fileExists(atPath: pets.appending(path: "ironman/sprites/sheet.png").path) ? pets : nil
}

@MainActor
@Suite struct PackLoadingTests {
    @Test func loadsValidPacksAndSkipsInvalidOnesWithAReason() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeFixturePack(id: "good", in: root)
        _ = try makeFixturePack(id: "badclip", in: root, clip: "missing")
        _ = try makeFixturePack(id: "tooshort", in: root, sceneSeconds: 1)
        let r = PetDirectories.loadAll(from: [root])
        #expect(r.packs.map(\.id) == ["good"])
        #expect(r.failures.count == 2)
        #expect(r.failures.contains { $0.contains("badclip") && $0.contains("not defined") })
        #expect(r.failures.contains { $0.contains("tooshort") && $0.contains("3–30s") })
    }

    @Test func firstDirectoryWinsForDuplicateIDs() throws {
        let a = tempDir(), b = tempDir()
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        _ = try makeFixturePack(id: "dup", in: a)
        _ = try makeFixturePack(id: "dup", in: b)
        let r = PetDirectories.loadAll(from: [a, b])
        #expect(r.packs.count == 1)
        // /var and /private/var are the same place: compare resolved paths.
        #expect(r.packs[0].data.directory.resolvingSymlinksInPath().path.hasPrefix(a.resolvingSymlinksInPath().path))
    }

    @Test func framesDecodeOnDemandAndPurge() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = try LoadedPack.load(from: try makeFixturePack(id: "lazy", in: root))
        #expect(pack.geometry["f0"]?.rect == CGRect(x: 0, y: 0, width: 8, height: 12))
        #expect(pack.frames["f0"]?.image.width == 8)
        pack.purgeImages()
        #expect(pack.frames["f0"] != nil) // decodes again
    }

    @Test func repoPacksAndEnsemblesValidate() throws {
        guard let pets = repoPets else { return } // sheets not built on this checkout
        let r = PetDirectories.loadAll(from: [pets])
        #expect(Set(r.packs.map(\.id)).isSuperset(of: ["ironman", "spiderman", "batman"]), "\(r.failures)")
        let ensembles = EnsembleLoader.load(from: pets.appending(path: "_ensembles"))
        #expect(ensembles.failures.isEmpty)
        for e in ensembles.ensembles {
            let errors = PackValidator.validate(e, pets: r.packs.map(\.data)).filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(e.id): \(errors)")
        }
    }
}

@MainActor
@Suite struct DirectorPlanningTests {
    func pack() throws -> LoadedPack {
        let root = tempDir()
        return try LoadedPack.load(from: try makeFixturePack(id: "p", in: root))
    }

    @Test func blockedWhenEveryCandidateHitsABlockingObstacle() throws {
        let p = try pack()
        let video = Obstacle(rect: testDisplay.frame, kind: .video)
        let d = SceneDirector(pack: p, scene: p.data.scenes[0], display: testDisplay, options: .init(), rng: SeededRandom(seed: 1),
                              obstacles: [video]) { _ in }
        #expect(d.isBlocked)
        let free = SceneDirector(pack: p, scene: p.data.scenes[0], display: testDisplay, options: .init(), rng: SeededRandom(seed: 1)) { _ in }
        #expect(!free.isBlocked)
        #expect(!free.hasStarted && !free.isRunning)
    }

    @Test func placementOverrideIsHonoured() throws {
        let p = try pack()
        let d = SceneDirector(pack: p, scene: p.data.scenes[0], display: testDisplay, options: .init(), rng: SeededRandom(seed: 1),
                              placement: (CGPoint(x: 321, y: 70), .right)) { _ in }
        #expect(d.anchor == CGPoint(x: 321, y: 70))
    }

    @Test func windowGrowsForSwingsAndBeams() throws {
        let p = try pack()
        var plain = p.data.scenes[0]
        let small = SceneDirector.box(for: plain, pack: p, scale: 4, display: testDisplay)
        var swing = StepDefinition(clip: "idle", motion: MotionSpec(type: .swing), duration: 3)
        swing.motion.attach = "top"
        plain.steps = [swing]
        plain.region = .air
        let big = SceneDirector.box(for: plain, pack: p, scale: 4, display: testDisplay)
        #expect(big.size.height > small.size.height + 200) // the rope reaches the top of the screen
        plain.steps = [StepDefinition(clip: "idle", duration: 3, effects: [EffectSpec("beam", params: ["length": .number(150)])])]
        let beam = SceneDirector.box(for: plain, pack: p, scale: 4, display: testDisplay)
        #expect(beam.size.width >= 2 * 150 * 4 * 0.9)
    }

    @Test func petsWithAHeightGetTheSameOnScreenHeight() throws {
        let p = try pack() // height 12 px
        #expect(abs(p.data.definition.renderScale(userScale: 0.8) * 12 - PetDefinition.standardHeight * 0.8) < 1e-9)
    }
}

@MainActor
struct SpeechBubbleTests {
    let size = CGSize(width: 150, height: 40)
    let screen = CGRect(x: 0, y: 0, width: 1500, height: 950)

    @Test func centredOverTheHeadWhenThereIsRoom() {
        let (r, tail) = SpeechBubble.layout(size: size, head: CGPoint(x: 700, y: 400), area: screen)
        #expect(abs(r.midX - 700) <= 1 && r.minY > 400 && tail == 700)
    }

    /// Peeking from either edge: the head is at the screen edge, so the bubble slides inwards.
    @Test(arguments: [CGPoint(x: 5, y: 300), CGPoint(x: 1495, y: 300)])
    func staysOnScreenAtAnEdge(head: CGPoint) {
        let (r, tail) = SpeechBubble.layout(size: size, head: head, area: screen)
        #expect(screen.contains(r))
        #expect(tail >= r.minX && tail <= r.maxX)
    }

    @Test func staysBelowTheTopOfTheScreen() {
        let (r, _) = SpeechBubble.layout(size: size, head: CGPoint(x: 700, y: 940), area: screen)
        #expect(r.maxY <= screen.maxY)
    }

    @Test func longerLinesStayUpLonger() {
        #expect(SpeechBubble.readingTime("Hi.") == 2.8)
        #expect(SpeechBubble.readingTime("Ninety minutes in. Stretch?") > 2.8)
        #expect(SpeechBubble.readingTime(String(repeating: "a", count: 300)) == 6)
    }
}
