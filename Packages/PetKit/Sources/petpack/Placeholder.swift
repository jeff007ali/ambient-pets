import Foundation
import PetCore
import PetImaging

/// Original placeholder art: a small armored hero in red and gold, drawn on a cell grid.
/// Uses the same frame names as the real Iron Man labels (`idle_0`, `walk_0`, `fly_0`, …), so packs work before the
/// real sheets are sliced, and swapping art later needs no scene changes.
enum PlaceholderArt {
    static let cell = 3

    static let red = RGBA(r: 196, g: 22, b: 32)
    static let darkRed = RGBA(r: 120, g: 12, b: 20)
    static let gold = RGBA(r: 236, g: 186, b: 52)
    static let darkGold = RGBA(r: 176, g: 128, b: 22)
    static let cyan = RGBA(r: 120, g: 232, b: 255)
    static let white = RGBA(r: 255, g: 255, b: 255)
    static let steel = RGBA(r: 70, g: 70, b: 78)
    static let ink = RGBA(r: 22, g: 16, b: 20)

    struct Canvas {
        let w: Int, h: Int
        var cells: [RGBA?]

        init(_ w: Int, _ h: Int) {
            self.w = w
            self.h = h
            cells = Array(repeating: nil, count: w * h)
        }

        mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: RGBA) {
            for yy in y..<(y + rh) where yy >= 0 && yy < h {
                for xx in x..<(x + rw) where xx >= 0 && xx < w { cells[yy * w + xx] = c }
            }
        }

        /// 1-cell dark outline around the figure: the classic sprite look.
        mutating func outline() {
            var out = cells
            for y in 0..<h {
                for x in 0..<w where cells[y * w + x] == nil {
                    let n = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    if n.contains(where: { $0.0 >= 0 && $0.1 >= 0 && $0.0 < w && $0.1 < h && cells[$0.1 * w + $0.0] != nil }) {
                        out[y * w + x] = PlaceholderArt.ink
                    }
                }
            }
            cells = out
        }

        func render() -> RGBAImage {
            let s = PlaceholderArt.cell
            var img = RGBAImage(width: w * s, height: h * s)
            for y in 0..<h {
                for x in 0..<w {
                    guard let c = cells[y * w + x] else { continue }
                    for dy in 0..<s { for dx in 0..<s { img.set(x * s + dx, y * s + dy, c) } }
                }
            }
            return img
        }
    }

    enum Arm { case down, forward, up, scratch, hover, ground }

    struct Pose {
        var drop = 0
        var backLeg = 0, frontLeg = 0
        var arm = Arm.down
        var kneel = false
        var pointedFeet = false
        var unibeam = false
    }

    /// Upright figure facing right on a 30×40 cell grid; feet on row 37.
    static func upright(_ p: Pose) -> RGBAImage {
        var c = Canvas(30, 40)
        let d = p.drop
        let hip = 23 + d

        // Back arm (behind the torso).
        switch p.arm {
        case .hover: c.rect(8, 12 + d, 3, 5, darkGold); c.rect(6, 17 + d, 3, 5, darkRed)
        case .up, .scratch, .forward: c.rect(9, 12 + d, 3, 9, darkRed)
        default: c.rect(8, 12 + d, 3, 4, darkGold); c.rect(8, 16 + d, 3, 6, darkRed)
        }

        // Legs: rows from the hip to the feet, shifted linearly towards the foot.
        func leg(_ base: Int, _ shift: Int, _ color: RGBA) {
            let rows = 37 - hip + 1
            for i in 0..<rows {
                let x = base + Int((Double(shift) * Double(i) / Double(max(rows - 1, 1))).rounded())
                let boot = i >= rows - 4
                c.rect(x, hip + i, 4, 1, boot ? darkRed : color)
                if boot && i >= rows - 2 && !p.pointedFeet { c.rect(x + 4, hip + i, 1, 1, darkRed) } // toe
            }
            if !p.pointedFeet { c.rect(base + shift + 1, hip + rows / 2 - 1, 2, 2, gold) } // knee plate
        }
        if p.kneel {
            // Superhero landing: front thigh forward, back knee down.
            c.rect(8, hip, 4, 37 - hip - 2, darkRed)
            c.rect(4, 35, 8, 3, darkRed)
            c.rect(15, hip, 7, 4, red)
            c.rect(19, hip + 4, 4, 37 - hip - 4, red)
            c.rect(19, 35, 5, 3, darkRed)
        } else {
            leg(11, p.backLeg, darkRed)
            leg(15, p.frontLeg, red)
        }

        // Torso.
        c.rect(10, 11 + d, 10, 11, red)
        c.rect(12, 17 + d, 6, 4, gold) // abs
        c.rect(10, 22 + d, 10, 1, darkGold) // belt
        if p.unibeam {
            c.rect(15, 12 + d, 5, 5, cyan)
            c.rect(16, 13 + d, 3, 3, white)
        } else {
            c.rect(16, 13 + d, 3, 3, cyan)
            c.rect(17, 14 + d, 1, 1, white)
        }

        // Head.
        c.rect(13, 10 + d, 4, 1, steel)
        c.rect(11, 2 + d, 8, 8, red)
        c.rect(14, 4 + d, 5, 6, gold) // faceplate
        c.rect(15, 5 + d, 4, 1, white) // eye slit
        c.rect(11, 2 + d, 1, 1, darkRed)

        // Front arm.
        switch p.arm {
        case .down:
            c.rect(16, 12 + d, 1, 10, darkRed)
            c.rect(17, 12 + d, 3, 4, gold)
            c.rect(17, 16 + d, 3, 6, red)
        case .forward:
            c.rect(17, 12 + d, 3, 3, gold)
            c.rect(20, 12 + d, 7, 3, red)
            c.rect(27, 12 + d, 1, 3, white)
        case .up:
            c.rect(17, 9 + d, 3, 4, gold)
            c.rect(17, 1 + d, 3, 8, red)
            c.rect(16, 0 + d, 5, 2, red)
        case .scratch:
            c.rect(17, 12 + d, 3, 4, gold)
            c.rect(19, 5 + d, 3, 8, red)
            c.rect(18, 3 + d, 4, 3, red)
        case .hover:
            c.rect(18, 12 + d, 3, 5, gold)
            c.rect(20, 17 + d, 3, 5, red)
            c.rect(20, 22 + d, 3, 1, cyan)
        case .ground:
            c.rect(17, 12 + d, 3, 4, gold)
            c.rect(19, 16 + d, 3, 37 - 16 - d, red)
            c.rect(19, 35, 4, 3, red)
        }
        c.outline()
        return c.render()
    }

    /// Horizontal flight facing right on a 44×20 cell grid.
    static func flying(flutter: Int) -> RGBAImage {
        var c = Canvas(44, 20)
        c.rect(5, 6 + flutter, 16, 4, darkRed) // back leg
        c.rect(1, 6 + flutter, 4, 4, darkRed)
        c.rect(21, 6, 13, 9, red) // torso
        c.rect(22, 11, 5, 3, gold)
        c.rect(29, 13, 3, 2, cyan) // reactor faces down
        c.rect(5, 10, 16, 4, red) // front leg
        c.rect(1, 10, 4, 4, darkRed)
        c.rect(12, 11, 2, 2, gold)
        c.rect(34, 5, 8, 8, red) // head
        c.rect(38, 6, 4, 7, gold)
        c.rect(39, 8, 3, 1, white)
        c.rect(25, 14, 5, 3, gold) // arm along the body, palm back
        c.rect(16, 14, 9, 3, red)
        c.rect(15, 14, 1, 3, cyan)
        c.outline()
        return c.render()
    }

    static func frames() -> [(String, RGBAImage)] {
        [
            ("idle_0", upright(Pose())),
            ("idle_1", upright(Pose(drop: 1))),
            ("walk_0", upright(Pose(backLeg: -3, frontLeg: 3))),
            ("walk_1", upright(Pose(drop: 1))),
            ("walk_2", upright(Pose(backLeg: 3, frontLeg: -3))),
            ("hover_0", upright(Pose(arm: .hover, pointedFeet: true))),
            ("hover_1", upright(Pose(backLeg: -1, frontLeg: 1, arm: .hover, pointedFeet: true))),
            ("land_0", upright(Pose(drop: 6, arm: .ground, kneel: true))),
            ("repulsor_0", upright(Pose(arm: .forward))),
            ("beam_0", upright(Pose(backLeg: -2, arm: .down, unibeam: true))),
            ("victory_0", upright(Pose(arm: .up))),
            ("confused_0", upright(Pose(arm: .scratch))),
            ("fly_0", flying(flutter: 0)),
            ("fly_1", flying(flutter: 1)),
        ]
    }

    /// Writes `sprites/sheet.png` + `sprites/atlas.json` into a pet directory.
    static func write(to petDir: URL) throws {
        // All upright poses share one grid, so they share one pivot (feet centre) — no jitter between poses.
        let items = frames().map { name, img in
            let pivot = img.height == 40 * cell ? [Int(15.5 * Double(cell)), 39 * cell]
                : SpriteSlicer.autoPivot(img, in: PixelRect(x: 0, y: 0, width: img.width, height: img.height))
            return SheetPacker.Item(name: name, image: img, pivot: pivot)
        }
        let (sheet, atlasFrames) = SheetPacker.pack(items, maxWidth: 640)
        let sprites = petDir.appending(path: "sprites")
        guard let image = sheet.makeCGImage() else { throw ImagingError.unwritable("sheet") }
        try ImageFiles.writePNG(image, to: sprites.appending(path: "sheet.png"))
        try writeJSON(SpriteAtlas(image: "sheet.png", facing: .right, frames: atlasFrames), to: sprites.appending(path: "atlas.json"))
        for item in items.sorted(by: { $0.name < $1.name }) {
            print("  \(item.name.padding(toLength: 12, withPad: " ", startingAt: 0)) \(item.image.width)×\(item.image.height) pivot \(item.pivot)")
        }
    }
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try e.encode(value).write(to: url, options: .atomic)
}
