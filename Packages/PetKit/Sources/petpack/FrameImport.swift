import Foundation
import PetCore
import PetImaging

/// `petpack frames`: builds a sheet from a folder of per-frame PNGs on a shared canvas (e.g. game rips with one file
/// per frame). Every frame keeps the same canvas anchor as its pivot, so poses keep the game's own placement.
///
/// labels.json:
/// ```
/// { "dir": "…/default", "facing": "right", "anchorFrom": "Idle_00.png",
///   "clips": { "idle": ["Idle_*"], "sense": ["Idle_00.png+Spidersense_*"], "land": ["Land_00.png", "Land_01.png"] } }
/// ```
/// - `Name_*` expands to every `Name_<n>.png`, ordered by frame number. File names may encode repeats:
///   `Attack_02-03.png` is frames 2 and 3, `Swing_04_08_12.png` is frames 4, 8 and 12.
/// - `A+B` composites B over A (each side may be a pattern; a single file is reused for every frame of the other).
struct FrameLabels: Codable {
    var dir: String
    var facing: String?
    /// Canvas point used as the pivot for every frame. Defaults to the feet of `anchorFrom`.
    var anchor: [Int]?
    var anchorFrom: String?
    var clips: [String: [String]]
    /// Per-clip pivot: "center" pivots each frame on its own centre (projectiles, effects); "left" on its left edge
    /// (beams that grow out of a muzzle).
    var pivotByClip: [String: String]?
}

enum FrameImport {
    /// Frame numbers encoded after the last name part: `_07`, `_02-03`, `_04_08_12`.
    static func frameNumbers(_ file: String, prefix: String) -> [Int] {
        let rest = file.dropFirst(prefix.count).replacingOccurrences(of: ".png", with: "")
        let parts = rest.split(separator: "_").map(String.init)
        var out: [Int] = []
        for p in parts {
            let r = p.split(separator: "-").compactMap { Int($0) }
            if r.count == 2, r[0] <= r[1] { out += Array(r[0]...r[1]) } else if r.count == 1 { out.append(r[0]) }
        }
        return out
    }

    /// Expands a pattern that may live in a sub/sibling folder of `dir` (e.g. `../projectiles/Shot_*`).
    static func expand(_ pattern: String, dir: URL) throws -> [String] {
        let folder = (pattern as NSString).deletingLastPathComponent
        let name = (pattern as NSString).lastPathComponent
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.appending(path: folder).path)
        return try expand(name, in: files).map { folder.isEmpty ? $0 : "\(folder)/\($0)" }
    }

    /// Expands `Name_*` into files in frame order (a file listed for several frame numbers repeats).
    static func expand(_ pattern: String, in files: [String]) throws -> [String] {
        guard pattern.hasSuffix("*") else {
            guard files.contains(pattern) else { throw CLIError("frames: no file '\(pattern)'") }
            return [pattern]
        }
        let prefix = String(pattern.dropLast())
        var numbered: [(Int, String)] = []
        for f in files where f.hasPrefix(prefix) && f.hasSuffix(".png") {
            let rest = f.dropFirst(prefix.count)
            guard rest.first?.isNumber == true else { continue } // "Walk_*" must not match "Walkstart.png"
            for n in frameNumbers(f, prefix: prefix) { numbered.append((n, f)) }
        }
        guard !numbered.isEmpty else { throw CLIError("frames: '\(pattern)' matched nothing") }
        return numbered.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func run(_ a: Args) throws {
        guard let labelsPath = a.positional.first, let out = a.options["out"] else {
            throw CLIError("frames: need <labels.json> --out <pet-dir>/sprites")
        }
        let labelsURL = url(labelsPath)
        let labels = try JSONDecoder().decode(FrameLabels.self, from: Data(contentsOf: labelsURL))
        // `dir` is relative to the current directory (repo root), like every other petpack path.
        let dir = url(labels.dir)
        var cache: [String: RGBAImage] = [:]
        func load(_ f: String) throws -> RGBAImage {
            if let i = cache[f] { return i }
            let i = RGBAImage(cgImage: try ImageFiles.load(dir.appending(path: f)))
            cache[f] = i
            return i
        }

        let anchor: [Int]
        if let a = labels.anchor {
            anchor = a
        } else {
            var ref = labels.anchorFrom ?? ""
            if ref.isEmpty, let first = labels.clips.values.first?.first {
                ref = try expand(String(first.split(separator: "+")[0]), dir: dir)[0]
            }
            let img = try load(ref)
            let all = PixelRect(x: 0, y: 0, width: img.width, height: img.height)
            let comps = SpriteSlicer.components(img)
            let bbox = comps.map(\.rect).reduce(comps.first?.rect ?? all) { $0.union($1) }
            let p = SpriteSlicer.autoPivot(img, in: bbox)
            anchor = [bbox.x + p[0], bbox.y + p[1]]
        }

        var items: [SheetPacker.Item] = []
        var suggested: [String: SuggestedClip] = [:]
        for (clip, entries) in labels.clips.sorted(by: { $0.key < $1.key }) {
            var names: [String] = []
            var seen: [String: String] = [:]
            for entry in entries {
                let layers = try entry.split(separator: "+").map { try expand(String($0), dir: dir) }
                let count = layers.map(\.count).max() ?? 0
                for i in 0..<count {
                    let key = layers.map { $0.count == 1 ? $0[0] : $0[min(i, $0.count - 1)] }.joined(separator: "+")
                    if let existing = seen[key] { names.append(existing); continue }
                    var canvas = try load(key.split(separator: "+").map(String.init)[0])
                    for over in key.split(separator: "+").dropFirst() { canvas.composite(try load(String(over))) }
                    let comps = SpriteSlicer.components(canvas)
                    // Fully transparent frames are deliberate pauses in some rips: keep them as a blank 1×1 frame.
                    let bbox = comps.first.map { first in comps.map(\.rect).reduce(first.rect) { $0.union($1) } }
                        ?? PixelRect(x: min(max(anchor[0], 0), canvas.width - 1), y: min(max(anchor[1] - 1, 0), canvas.height - 1), width: 1, height: 1)
                    let name = "\(clip)_\(seen.count)"
                    seen[key] = name
                    names.append(name)
                    let pivot: [Int] = switch labels.pivotByClip?[clip] {
                    case "center": [bbox.width / 2, bbox.height / 2]
                    case "left": [0, bbox.height / 2] // beams: anchored at the muzzle end
                    default: [anchor[0] - bbox.x, anchor[1] - bbox.y]
                    }
                    items.append(SheetPacker.Item(name: name, image: canvas.cropped(bbox), pivot: pivot))
                }
            }
            suggested[clip] = SuggestedClip(frames: names, fps: 12, loop: true)
        }
        let (sheet, frames) = SheetPacker.pack(items)
        let outURL = url(out)
        guard let image = sheet.makeCGImage() else { throw CLIError("empty sheet") }
        try ImageFiles.writePNG(image, to: outURL.appending(path: "sheet.png"))
        try writeJSON(SpriteAtlas(image: "sheet.png", facing: Facing(rawValue: labels.facing ?? "right") ?? .right, frames: frames),
                      to: outURL.appending(path: "atlas.json"))
        try writeJSON(["clips": suggested], to: outURL.appending(path: "clips.suggested.json"))
        print("anchor \(anchor); packed \(items.count) frames into \(sheet.width)×\(sheet.height) sheet → \(out)")
    }
}
