import CoreGraphics
import Foundation
import PetCore
import PetImaging

let usage = """
petpack — Ambient Pets pack tool

USAGE
  petpack validate <pet-dir>...
      Check pack files: atlas, clips (fallback cycles), scenes (clips, motions, effects, sounds, durations).

  petpack slice <sheet.png> --out <dir> [--bg #RRGGBB] [--merge 3] [--min-pixels 16] [--tolerance 8]
      Key out the background, detect sprites, and write <dir>/candidates.json, <dir>/contact.png
      (numbered frames for labelling) and <dir>/keyed.png.

  petpack pack <dir>/candidates.json <labels.json> --out <pet-dir>/sprites [--facing right]
      Pack only the labelled frames into sheet.png + atlas.json (+ clips.suggested.json).
      labels.json: { "clips": { "fly": [12, 13, 14, 13], … }, "pivots": { "12": [58, 90] }, "flip": [12, 13],
                     "pivot": "feet" | "torso" | "center" | "left", "pivotByClip": { "walk": "torso" },
                     "extra": [{ "work": "<other-slice-dir>", "scale": 0.8, "clips": { … } }] }
      `extra` packs frames from more sliced sheets of the same character into the same atlas, resized to match.

  petpack frames <labels.json> --out <pet-dir>/sprites
      Build a sheet from a folder of per-frame PNGs on a shared canvas (one file per frame), keeping a common
      canvas anchor as every frame's pivot. See FrameImport.swift for the labels format.

  petpack preview <pet-dir> <clip> [--out clip.gif|clip.png] [--zoom 2]
      Animated GIF of a clip, frames aligned on their pivots (for checking pivots and timing).
      A .png output writes the aligned frames side by side instead.

  petpack placeholder <pet-dir>
      Generate original placeholder art (sheet.png + atlas.json) with the standard frame names.

  petpack info <pet-dir>
      Summary of a pack.
"""

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

struct Args {
    var positional: [String] = []
    var options: [String: String] = [:]

    init(_ raw: ArraySlice<String>) {
        var it = raw.makeIterator()
        while let a = it.next() {
            if a.hasPrefix("--") { options[String(a.dropFirst(2))] = it.next() ?? "" } else { positional.append(a) }
        }
    }

    func int(_ k: String) -> Int? { options[k].flatMap(Int.init) }
}

func url(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }

// MARK: - Commands

func validate(_ dirs: [String]) throws -> Bool {
    guard !dirs.isEmpty else { throw CLIError("validate: give at least one pet directory") }
    var ok = true
    for dir in dirs {
        let u = url(dir)
        // An ensembles folder (no pet.json): check every shared scene against the sibling packs.
        if !FileManager.default.fileExists(atPath: u.appending(path: "pet.json").path), u.lastPathComponent == "_ensembles" {
            let siblings = ((try? FileManager.default.contentsOfDirectory(at: u.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? [])
                .compactMap { try? PetPackData.load(from: $0) }
            let loaded = EnsembleLoader.load(from: u)
            for f in loaded.failures { print("✘ _ensembles/\(f)"); ok = false }
            for e in loaded.ensembles {
                let issues = PackValidator.validate(e, pets: siblings)
                let errors = issues.filter { $0.severity == .error }
                print("\(errors.isEmpty ? "✔" : "✘") ensemble \(e.id): \(e.roles.count) roles, \(errors.count) errors, \(issues.count - errors.count) warnings")
                for i in issues { print("    \(i)") }
                ok = ok && errors.isEmpty
            }
            continue
        }
        do {
            let pack = try PetPackData.load(from: u)
            let image = try? ImageFiles.load(pack.atlasImageURL)
            let issues = PackValidator.validate(pack, imageSize: image.map { CGSize(width: $0.width, height: $0.height) })
            let errors = issues.filter { $0.severity == .error }
            print("\(errors.isEmpty ? "✔" : "✘") \(pack.id) (\(u.lastPathComponent)): \(pack.scenes.count) scenes, \(pack.clips.clips.count) clips, \(errors.count) errors, \(issues.count - errors.count) warnings")
            for i in issues { print("    \(i)") }
            ok = ok && errors.isEmpty
        } catch {
            print("✘ \(u.lastPathComponent): \(error.localizedDescription)")
            ok = false
        }
    }
    return ok
}

struct Candidates: Codable {
    var source: String
    var background: String?
    var frames: [SlicedFrame]
}

func slice(_ a: Args) throws {
    guard let sheetPath = a.positional.first, let out = a.options["out"] else { throw CLIError("slice: need <sheet.png> --out <dir>") }
    var img = RGBAImage(cgImage: try ImageFiles.load(url(sheetPath)))
    var opts = SpriteSlicer.Options(background: try a.options["bg"].map {
        guard let c = RGBA(hex: $0) else { throw CLIError("bad --bg colour \($0)") }
        return c
    })
    opts.mergeDistance = a.int("merge") ?? opts.mergeDistance
    opts.minPixels = a.int("min-pixels") ?? opts.minPixels
    opts.tolerance = a.int("tolerance") ?? opts.tolerance
    let (bg, frames) = SpriteSlicer.slice(&img, options: opts)
    let outURL = url(out)
    try writeJSON(Candidates(source: url(sheetPath).path, background: bg?.hex, frames: frames), to: outURL.appending(path: "candidates.json"))
    if let keyed = img.makeCGImage() { try ImageFiles.writePNG(keyed, to: outURL.appending(path: "keyed.png")) }
    if let contact = ContactSheet.render(source: img, frames: frames) {
        try ImageFiles.writePNG(contact, to: outURL.appending(path: "contact.png"))
    }
    print("background \(bg?.hex ?? "none (already transparent)"); \(frames.count) frames")
    print("wrote \(out)/candidates.json, contact.png, keyed.png. Next: write labels.json, then `petpack pack`.")
}

struct Labels: Codable {
    var clips: [String: [Int]]
    /// Per-frame pivot overrides (frame-relative, top-left origin, after any flip).
    var pivots: [String: [Int]]?
    /// Frames to mirror horizontally, so a sheet with mixed facings ends up facing one way.
    var flip: [Int]?
    /// Auto-pivot mode: "feet" (default; bottom-centre of the feet) or "torso" (chest centre, feet height).
    var pivot: String?
    /// Per-clip pivot mode overrides.
    var pivotByClip: [String: String]?
    /// More sliced sheets of the same character (another game or version), packed into the same atlas. Their frame
    /// numbers, flips and pivot overrides refer to their own `candidates.json`.
    var extra: [ExtraSource]?
}

/// A second sheet for `pack`: `work` is its slice folder (candidates.json + keyed.png); `scale` resizes its frames
/// (nearest neighbour) so the character matches the main sheet's size.
struct ExtraSource: Codable {
    var work: String
    var scale: Double?
    var clips: [String: [Int]]
    var pivots: [String: [Int]]?
    var flip: [Int]?
    var pivot: String?
    var pivotByClip: [String: String]?
}

struct SuggestedClip: Codable {
    var frames: [String]
    var fps: Double
    var loop: Bool
}

func pack(_ a: Args) throws {
    guard a.positional.count == 2, let out = a.options["out"] else {
        throw CLIError("pack: need <candidates.json> <labels.json> --out <pet-dir>/sprites")
    }
    let candURL = url(a.positional[0])
    let labels = try JSONDecoder().decode(Labels.self, from: Data(contentsOf: url(a.positional[1])))
    var sources = [ExtraSource(work: candURL.deletingLastPathComponent().path, scale: nil, clips: labels.clips,
                               pivots: labels.pivots, flip: labels.flip, pivot: labels.pivot, pivotByClip: labels.pivotByClip)]
    sources += labels.extra ?? []

    var items: [SheetPacker.Item] = []
    var suggested: [String: SuggestedClip] = [:]
    for source in sources {
        let work = url(source.work)
        let cands = try JSONDecoder().decode(Candidates.self, from: Data(contentsOf: work.appending(path: "candidates.json")))
        let keyed = RGBAImage(cgImage: try ImageFiles.load(work.appending(path: "keyed.png")))
        let byIndex = Dictionary(uniqueKeysWithValues: cands.frames.map { ($0.index, $0) })
        let scale = source.scale ?? 1
        for (label, indices) in source.clips.sorted(by: { $0.key < $1.key }) {
            guard suggested[label] == nil else { throw CLIError("clip '\(label)' is labelled in more than one sheet") }
            var seen: [Int: String] = [:]
            var clipFrames: [String] = []
            for idx in indices {
                guard let f = byIndex[idx] else { throw CLIError("label '\(label)' uses unknown frame index \(idx) in \(source.work)") }
                if let existing = seen[idx] { clipFrames.append(existing); continue }
                let name = "\(label)_\(seen.count)"
                seen[idx] = name
                clipFrames.append(name)
                var image = keyed.cropped(f.rect)
                let mode = source.pivotByClip?[label] ?? source.pivot ?? "feet"
                var pivot = switch mode {
                case "torso": SpriteSlicer.torsoPivot(keyed, in: f.rect)
                case "center": [f.rect.width / 2, f.rect.height / 2]
                case "left": [0, f.rect.height / 2] // beams: anchored at the muzzle end
                default: f.pivot
                }
                if source.flip?.contains(idx) == true {
                    image = image.mirrored()
                    pivot = [f.rect.width - pivot[0], pivot[1]]
                }
                pivot = source.pivots?[String(idx)] ?? pivot
                if scale != 1 {
                    image = image.scaled(scale)
                    pivot = pivot.map { Int((Double($0) * scale).rounded()) }
                }
                items.append(SheetPacker.Item(name: name, image: image, pivot: pivot))
            }
            suggested[label] = SuggestedClip(frames: clipFrames, fps: 8, loop: true)
        }
    }
    let (sheet, frames) = SheetPacker.pack(items)
    let outURL = url(out)
    guard let image = sheet.makeCGImage() else { throw CLIError("empty sheet") }
    let facing = Facing(rawValue: a.options["facing"] ?? "right") ?? .right
    try ImageFiles.writePNG(image, to: outURL.appending(path: "sheet.png"))
    try writeJSON(SpriteAtlas(image: "sheet.png", facing: facing, frames: frames), to: outURL.appending(path: "atlas.json"))
    try writeJSON(["clips": suggested], to: outURL.appending(path: "clips.suggested.json"))
    print("packed \(items.count) frames into \(sheet.width)×\(sheet.height) sheet → \(out)")
    print("merge clips.suggested.json into ../clips.json (set fps/loop/points), then `petpack validate`.")
}

func preview(_ a: Args) throws {
    guard a.positional.count == 2 else { throw CLIError("preview: need <pet-dir> <clip>") }
    let packData = try PetPackData.load(from: url(a.positional[0]))
    let clipID = a.positional[1]
    let clip: ResolvedClip
    switch packData.clips.resolve(clipID) {
    case .success(let c): clip = c
    case .failure(let e): throw CLIError("\(e)")
    }
    let sheet = try ImageFiles.load(packData.atlasImageURL)
    let cut = FrameCutter.cut(atlas: packData.atlas, image: sheet)
    let zoom = a.int("zoom") ?? 2
    let used = clip.frames.compactMap { cut[$0] }
    guard used.count == clip.frames.count else { throw CLIError("clip references frames missing from the atlas") }
    let e = used.map(\.frame.extents).reduce(SpriteExtents.zero) { $0.union($1) }
    let w = Int(e.left + e.right) + 8, h = Int(e.up + e.down) + 8
    var images: [CGImage] = []
    for (img, f) in used {
        let ctx = CGContext(data: nil, width: w * zoom, height: h * zoom, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.setFillColor(CGColor(gray: 0.82, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w * zoom, height: h * zoom))
        // Pivot at (4 + left, 4 + down) from the bottom-left; draw the frame so its pivot lands there.
        let px = 4 + e.left, py = 4 + e.down
        let rect = CGRect(x: (px - f.pivot.x) * Double(zoom), y: (py - (f.rect.height - f.pivot.y)) * Double(zoom),
                          width: f.rect.width * Double(zoom), height: f.rect.height * Double(zoom))
        ctx.draw(img, in: rect)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: px * Double(zoom) - 3, y: py * Double(zoom) - 1, width: 6, height: 2))
        images.append(ctx.makeImage()!)
    }
    let out = a.options["out"] ?? "\(clipID).gif"
    if out.hasSuffix(".png") {
        // A strip of the pivot-aligned frames side by side (easy to inspect without playing a GIF).
        let fw = images[0].width, fh = images[0].height
        let ctx = CGContext(data: nil, width: fw * images.count, height: fh, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (i, img) in images.enumerated() { ctx.draw(img, in: CGRect(x: i * fw, y: 0, width: fw, height: fh)) }
        try ImageFiles.writePNG(ctx.makeImage()!, to: url(out))
    } else {
        try ImageFiles.writeGIF(images, delay: 1 / max(clip.definition.fps, 0.5), to: url(out))
    }
    print("\(clipID) → \(clip.sourceID): \(clip.frames.count) frames @ \(clip.definition.fps) fps → \(out)")
}

func info(_ a: Args) throws {
    guard let dir = a.positional.first else { throw CLIError("info: need <pet-dir>") }
    let p = try PetPackData.load(from: url(dir))
    print("\(p.definition.name) (\(p.id)) v\(p.definition.version ?? "?"), renderer \(p.definition.renderer), scale \(p.definition.defaultScale)")
    print("atlas: \(p.atlas.frames.count) frames, facing \(p.atlas.facing.rawValue)")
    let clips = p.clips.clips.keys.sorted().map { id -> String in
        if case .success(let c) = p.clips.resolve(id), c.sourceID != id { return "\(id)→\(c.sourceID)" }
        return id
    }
    print("clips: \(clips.joined(separator: ", "))")
    for s in p.scenes {
        print("scene \(s.id): \(s.tier.rawValue), \(String(format: "%.1f", s.totalDuration))s, \(s.steps.count) steps, region \(s.region.rawValue)")
    }
}

// MARK: - Main

let argv = CommandLine.arguments.dropFirst()
guard let command = argv.first else { print(usage); exit(0) }
let args = Args(argv.dropFirst())
do {
    switch command {
    case "validate": exit(try validate(args.positional) ? 0 : 1)
    case "slice": try slice(args)
    case "pack": try pack(args)
    case "frames": try FrameImport.run(args)
    case "preview": try preview(args)
    case "info": try info(args)
    case "placeholder":
        guard let dir = args.positional.first else { throw CLIError("placeholder: need <pet-dir>") }
        try PlaceholderArt.write(to: url(dir))
        print("wrote placeholder sheet.png + atlas.json to \(dir)/sprites")
    case "help", "-h", "--help": print(usage)
    default: throw CLIError("unknown command '\(command)'\n\n\(usage)")
    }
} catch {
    FileHandle.standardError.write(Data("petpack: \(error)\n".utf8))
    exit(1)
}
