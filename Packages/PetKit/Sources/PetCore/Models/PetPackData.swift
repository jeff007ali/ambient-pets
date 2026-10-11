import Foundation

public enum PackLoadError: Error, LocalizedError {
    case missingFile(String)
    case decode(file: String, reason: String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let f): "missing file: \(f)"
        case .decode(let f, let r): "\(f): \(r)"
        case .unsupportedVersion(let v): "formatVersion \(v) is newer than this engine supports (\(supportedFormatVersion))"
        }
    }
}

/// Loads every `*.json` ensemble in a directory (e.g. `Pets/_ensembles`), skipping invalid files with a reason.
public enum EnsembleLoader {
    public static func load(from directory: URL) -> (ensembles: [EnsembleScene], failures: [String]) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var out: [EnsembleScene] = [], failures: [String] = []
        for f in files {
            do {
                out.append(try JSONDecoder().decode(EnsembleScene.self, from: Data(contentsOf: f)))
            } catch {
                failures.append("\(f.lastPathComponent): \(describeDecodingError(error))")
            }
        }
        return (out, failures)
    }
}

/// Everything in a pet pack directory except the decoded images.
public struct PetPackData: Sendable {
    public let directory: URL
    public let definition: PetDefinition
    public let atlas: SpriteAtlas
    public let clips: ClipLibrary
    public let scenes: [SceneDefinition]
    /// Speech pools: pool name → lines.
    public let lines: [String: [String]]
    /// Optional `blocks.json`: building blocks for AI-composed routines.
    public let routines: RoutineLibrary?

    public var id: String { definition.id }
    public var atlasImageURL: URL { directory.appending(path: "sprites").appending(path: atlas.image) }

    public init(directory: URL, definition: PetDefinition, atlas: SpriteAtlas, clips: ClipLibrary,
                scenes: [SceneDefinition], lines: [String: [String]], routines: RoutineLibrary? = nil) {
        self.directory = directory
        self.definition = definition
        self.atlas = atlas
        self.clips = clips
        self.scenes = scenes
        self.lines = lines
        self.routines = routines
    }

    /// Loads `pet.json`, `sprites/atlas.json`, `clips.json`, `scenes/*.json` and (optional) `lines.json`.
    public static func load(from directory: URL) throws -> PetPackData {
        let definition = try decode(PetDefinition.self, directory, "pet.json")
        guard definition.formatVersion <= supportedFormatVersion else {
            throw PackLoadError.unsupportedVersion(definition.formatVersion)
        }
        let atlas = try decode(SpriteAtlas.self, directory, "sprites/atlas.json")
        let clips = try decode(ClipsFile.self, directory, "clips.json")

        let scenesDir = directory.appending(path: "scenes")
        let sceneFiles = ((try? FileManager.default.contentsOfDirectory(at: scenesDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let scenes = try sceneFiles.map { try decode(SceneDefinition.self, directory, "scenes/\($0.lastPathComponent)") }

        let linesURL = directory.appending(path: "lines.json")
        let lines = FileManager.default.fileExists(atPath: linesURL.path)
            ? try decode([String: [String]].self, directory, "lines.json")
            : [:]

        let blocksURL = directory.appending(path: "blocks.json")
        let routines = FileManager.default.fileExists(atPath: blocksURL.path)
            ? try decode(RoutineLibrary.self, directory, "blocks.json")
            : nil

        return PetPackData(directory: directory, definition: definition, atlas: atlas,
                           clips: ClipLibrary(clips.clips), scenes: scenes, lines: lines, routines: routines)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ dir: URL, _ relative: String) throws -> T {
        let url = dir.appending(path: relative)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw PackLoadError.missingFile(relative)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PackLoadError.decode(file: relative, reason: describeDecodingError(error))
        }
    }
}
