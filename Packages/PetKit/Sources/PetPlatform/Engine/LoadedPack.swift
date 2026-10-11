import CoreGraphics
import Foundation
import os
import PetCore
import PetImaging

let log = Logger(subsystem: "dev.jefflabs.AmbientPets", category: "engine")

/// A cut sprite frame ready for a CALayer.
public struct SpriteFrame {
    public let image: CGImage
    public let frame: ResolvedFrame
}

/// A validated pack. Frame geometry is always resident; the decoded sheet is loaded on first use (a scene starting)
/// and released with `purgeImages()` when the pet leaves, so idle memory stays small however many pets are installed.
@MainActor
public final class LoadedPack: Identifiable {
    public let data: PetPackData
    /// Frame rects and pivots (no pixels).
    public let geometry: [String: ResolvedFrame]
    public let warnings: [ValidationIssue]
    private var imageCache: [String: SpriteFrame]?

    public nonisolated var id: String { data.id }
    public var name: String { data.definition.name }

    init(data: PetPackData, geometry: [String: ResolvedFrame], warnings: [ValidationIssue]) {
        self.data = data
        self.geometry = geometry
        self.warnings = warnings
    }

    /// Cut frames with pixels, decoding the sheet if needed.
    public var frames: [String: SpriteFrame] {
        if let imageCache { return imageCache }
        let loaded: [String: SpriteFrame]
        if let image = try? ImageFiles.load(data.atlasImageURL) {
            loaded = FrameCutter.cut(atlas: data.atlas, image: image).mapValues { SpriteFrame(image: $0.image, frame: $0.frame) }
        } else {
            log.error("\(self.id, privacy: .public): sprite sheet became unreadable")
            loaded = [:]
        }
        imageCache = loaded
        return loaded
    }

    /// Drops the decoded sheet; the next scene decodes it again.
    public func purgeImages() { imageCache = nil }

    /// Loads and validates. Throws with every validation error if the pack is unusable. Reads only the sheet's size.
    public static func load(from directory: URL) throws -> LoadedPack {
        let data = try PetPackData.load(from: directory)
        let size = ImageFiles.pixelSize(data.atlasImageURL)
        let issues = PackValidator.validate(data, imageSize: size)
        let errors = issues.filter { $0.severity == .error }
        guard errors.isEmpty, let size else { throw PackInvalid(issues: errors) }
        let geometry = data.atlas.resolvedFrames(imageWidth: Int(size.width), imageHeight: Int(size.height))
        return LoadedPack(data: data, geometry: geometry, warnings: issues.filter { $0.severity == .warning })
    }

    /// Union of frame extents across the clips a scene uses (native px).
    public func extents(for scene: SceneDefinition) -> SpriteExtents {
        var e = SpriteExtents.zero
        for id in scene.clipIDs {
            for name in data.clips.resolveOrDefault(id)?.frames ?? [] {
                if let f = geometry[name] { e = e.union(f.extents) }
            }
        }
        return e
    }

    public func scene(_ id: String) -> SceneDefinition? { data.scenes.first { $0.id == id } }
}

public struct PackInvalid: Error, LocalizedError {
    public let issues: [ValidationIssue]
    public var errorDescription: String? { issues.map(\.message).joined(separator: "; ") }
}

/// Where pet packs are looked up, in priority order (an id found earlier wins).
public enum PetDirectories {
    /// `~/Library/Application Support/AmbientPets/Pets`
    public static var user: URL {
        HistoryStore.defaultURL.deletingLastPathComponent().appending(path: "Pets")
    }

    /// Shared multi-pet scenes, next to the bundled packs (`Pets/_ensembles`).
    public static func ensembleDirectories(from roots: [URL]) -> [URL] {
        roots.map { $0.appending(path: "_ensembles") }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func all() -> [URL] {
        var dirs: [URL] = []
        if let env = ProcessInfo.processInfo.environment["AMBIENT_PETS_DIR"] { dirs.append(URL(fileURLWithPath: env)) }
        if let res = Bundle.main.resourceURL?.appending(path: "Pets") { dirs.append(res) }
        // Dev fallback when run unbundled (`swift run`): walk up from the executable to the repo's Pets/.
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appending(path: "Pets")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "ironman/pet.json").path) {
                dirs.append(candidate)
                break
            }
            dir.deleteLastPathComponent()
        }
        dirs.append(user)
        return dirs
    }

    /// Loads every pack found; invalid packs are skipped with a reason.
    @MainActor
    public static func loadAll(from roots: [URL]) -> (packs: [LoadedPack], failures: [String]) {
        var packs: [LoadedPack] = []
        var failures: [String] = []
        var seen = Set<String>()
        for root in roots {
            let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for dir in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where FileManager.default.fileExists(atPath: dir.appending(path: "pet.json").path) {
                do {
                    let pack = try LoadedPack.load(from: dir)
                    guard seen.insert(pack.id).inserted else { continue }
                    for w in pack.warnings { log.info("\(pack.id, privacy: .public): \(w.message, privacy: .public)") }
                    packs.append(pack)
                } catch {
                    let reason = "\(dir.lastPathComponent): \(error.localizedDescription)"
                    log.error("skipping pack \(reason, privacy: .public)")
                    failures.append(reason)
                }
            }
        }
        return (packs, failures)
    }
}
