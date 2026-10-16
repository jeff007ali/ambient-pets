import CoreGraphics
import Foundation

public struct ValidationIssue: Sendable, Hashable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }
    public var severity: Severity
    public var message: String

    public static func error(_ m: String) -> ValidationIssue { ValidationIssue(severity: .error, message: m) }
    public static func warning(_ m: String) -> ValidationIssue { ValidationIssue(severity: .warning, message: m) }

    public var description: String { "\(severity.rawValue): \(message)" }
}

/// Static checks on a pack. Invalid packs are skipped by the app with the logged reason, never crash it.
public enum PackValidator {
    public static let sceneDurationRange = 3.0...30.0

    /// Ensemble checks against the packs that might play it: roles, waits, durations, and that every role's clips
    /// resolve for at least one pet that can take the role.
    public static func validate(_ e: EnsembleScene, pets: [PetPackData]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let ids = Set(e.roles.map(\.id))
        if e.roles.count < 2 { issues.append(.error("ensemble '\(e.id)': needs at least two roles")) }
        if ids.count != e.roles.count { issues.append(.error("ensemble '\(e.id)': duplicate role ids")) }
        for role in e.roles {
            let r = "ensemble '\(e.id)' role '\(role.id)'"
            let total = role.steps.reduce(0) { $0 + $1.duration }
            if !sceneDurationRange.contains(total) { issues.append(.error("\(r) lasts \(total)s; must be within 3–30s")) }
            for (i, step) in role.steps.enumerated() {
                if let w = step.waitFor {
                    guard let (other, n) = EnsemblePlanner.parseWait(w), ids.contains(other), other != role.id, n >= 1 else {
                        issues.append(.error("\(r) step \(i + 1): bad waitFor '\(w)'")); continue
                    }
                    if n != Int.max, let o = e.roles.first(where: { $0.id == other }), n > o.steps.count {
                        issues.append(.error("\(r) step \(i + 1): waitFor '\(w)' but role '\(other)' has \(o.steps.count) steps"))
                    }
                }
            }
            let able = pets.filter { p in role.requires.allSatisfy { p.definition.has($0) } }
            if able.isEmpty { issues.append(.warning("\(r): no installed pet has \(role.requires)")) }
            for p in able {
                for step in role.steps {
                    if case .failure(let err) = p.clips.resolve(step.clip) { issues.append(.error("\(r) as \(p.id): \(err)")) }
                }
            }
        }
        return issues
    }

    /// - Parameter imageSize: size of the atlas image in px, if it could be read.
    public static func validate(_ pack: PetPackData, imageSize: CGSize?) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let def = pack.definition

        if def.formatVersion > supportedFormatVersion {
            issues.append(.error("pet.json formatVersion \(def.formatVersion) > supported \(supportedFormatVersion)"))
        }
        if def.renderer != "sprite" { issues.append(.error("renderer '\(def.renderer)' is not supported (only 'sprite')")) }
        if def.id.isEmpty { issues.append(.error("pet.json: empty id")) }

        // Atlas
        var frames: [String: ResolvedFrame] = [:]
        if let size = imageSize {
            frames = pack.atlas.resolvedFrames(imageWidth: Int(size.width), imageHeight: Int(size.height))
            let bounds = CGRect(origin: .zero, size: size)
            for (name, f) in frames.sorted(by: { $0.key < $1.key }) where !bounds.contains(f.rect) {
                issues.append(.error("atlas frame '\(name)' \(f.rect) is outside the \(Int(size.width))×\(Int(size.height)) image"))
            }
        } else {
            issues.append(.error("atlas image '\(pack.atlas.image)' is missing or unreadable"))
            for (name, f) in pack.atlas.frames {
                if let r = f.resolved { frames[name] = r } else { issues.append(.error("atlas frame '\(name)' has an invalid rect")) }
            }
        }
        if frames.isEmpty { issues.append(.error("atlas has no frames")) }

        // Clips. Grid frame names are only known once the image size is.
        let canCheckFrames = imageSize != nil || pack.atlas.grid == nil
        for (id, clip) in pack.clips.clips.sorted(by: { $0.key < $1.key }) {
            if case .failure(let e) = pack.clips.resolve(id) { issues.append(.error("clip '\(id)': \(e)")) }
            for f in clip.frames ?? [] where canCheckFrames && frames[f] == nil {
                issues.append(.error("clip '\(id)' references unknown frame '\(f)'"))
            }
            if clip.fps <= 0 { issues.append(.error("clip '\(id)': fps must be > 0")) }
        }
        if case .failure = pack.clips.resolve("idle") {
            issues.append(.warning("no playable 'idle' clip; unknown clips will fall back to an arbitrary clip"))
        }

        // Scenes
        if pack.scenes.isEmpty { issues.append(.error("no scenes in scenes/")) }
        var seen = Set<String>()
        for scene in pack.scenes {
            let s = "scene '\(scene.id)'"
            if !seen.insert(scene.id).inserted { issues.append(.error("duplicate scene id '\(scene.id)'")) }
            if scene.steps.isEmpty { issues.append(.error("\(s) has no steps")) }
            if !sceneDurationRange.contains(scene.totalDuration) {
                issues.append(.error("\(s) lasts \(scene.totalDuration)s; must be within \(Int(sceneDurationRange.lowerBound))–\(Int(sceneDurationRange.upperBound))s"))
            }
            if !SceneRegion.known.contains(scene.region) { issues.append(.warning("\(s): unknown region '\(scene.region.rawValue)' (treated as bottom_edge)")) }
            for c in scene.allowedContexts where ContextState(rawValue: c) == nil {
                issues.append(.error("\(s): unknown context '\(c)'"))
            }
            for cap in scene.requires?.capabilities ?? [] where !def.has(cap) {
                issues.append(.warning("\(s) requires capability '\(cap)', which the pet does not declare; it will never play"))
            }
            for (i, step) in scene.steps.enumerated() {
                let p = "\(s) step \(i + 1)"
                if step.duration <= 0 { issues.append(.error("\(p): duration must be > 0")) }
                if case .failure(let e) = pack.clips.resolve(step.clip) { issues.append(.error("\(p): \(e)")) }
                if let hold = Self.frozenTail(step, clips: pack.clips) {
                    issues.append(.warning("\(p): '\(step.clip)' finishes \(String(format: "%.2f", hold)) s before the step ends, so the pet freezes on its last frame (shorten the step or lower the clip's fps)"))
                }
                let m = step.motion.type
                if MotionType.planned.contains(m) {
                    issues.append(.warning("\(p): motion '\(m.rawValue)' is not implemented yet and plays as 'none'"))
                } else if !MotionType.supported.contains(m) {
                    issues.append(.error("\(p): unknown motion '\(m.rawValue)'"))
                }
                for ref in [step.motion.from, step.motion.to].compactMap({ $0 }) where !AnchorRef.known.contains(ref) {
                    issues.append(.error("\(p): unknown anchor '\(ref)'"))
                }
                for fx in step.effects where fx.type == .projectile || fx.type == .overlay {
                    for key in ["clip", "hit"] {
                        guard let id = fx.string(key) else {
                            if key == "clip" { issues.append(.error("\(p): \(fx.type.rawValue) needs a 'clip'")) }
                            continue
                        }
                        if case .failure(let e) = pack.clips.resolve(id) { issues.append(.error("\(p): \(fx.type.rawValue) \(key): \(e)")) }
                    }
                }
                for fx in step.effects {
                    if EffectType.planned.contains(fx.type) {
                        issues.append(.warning("\(p): effect '\(fx.type.rawValue)' is not implemented yet"))
                    } else if !EffectType.supported.contains(fx.type) {
                        issues.append(.error("\(p): unknown effect '\(fx.type.rawValue)'"))
                    }
                }
                if let sound = step.sound, def.sounds[sound] == nil {
                    issues.append(.error("\(p): unknown sound '\(sound)' (add it to pet.json 'sounds')"))
                }
                if let pool = step.speech?.pool, (pack.lines[pool] ?? []).isEmpty {
                    issues.append(.error("\(p): speech pool '\(pool)' is missing or empty in lines.json"))
                }
                if let f = step.facing, !["left", "right", "toward_center", "away_from_center", "keep", "auto", "cursor", "partner"].contains(f) {
                    issues.append(.error("\(p): unknown facing '\(f)'"))
                }
            }
        }
        // Routine blocks: every clip resolves; enter + exit + one block fits the duration rule.
        if let r = pack.routines {
            let frame = (r.enter + r.exit).reduce(0) { $0 + $1.duration }
            if r.enter.isEmpty || r.exit.isEmpty { issues.append(.error("blocks.json: needs non-empty enter and exit")) }
            if r.blocks.count < RoutineComposer.minBlocks { issues.append(.error("blocks.json: needs at least \(RoutineComposer.minBlocks) blocks")) }
            for (name, steps) in [("enter", r.enter), ("exit", r.exit)] + r.blocks.sorted(by: { $0.key < $1.key }).map({ ($0.key, $0.value.steps) }) {
                for step in steps {
                    if case .failure(let e) = pack.clips.resolve(step.clip) { issues.append(.error("blocks.json '\(name)': \(e)")) }
                    for fx in step.effects where !EffectType.supported.contains(fx.type) {
                        issues.append(.error("blocks.json '\(name)': unknown effect '\(fx.type.rawValue)'"))
                    }
                    if let sound = step.sound, def.sounds[sound] == nil { issues.append(.error("blocks.json '\(name)': unknown sound '\(sound)'")) }
                }
                if steps.isEmpty { issues.append(.error("blocks.json '\(name)': no steps")) }
            }
            if frame >= PackValidator.sceneDurationRange.upperBound - 4 { issues.append(.error("blocks.json: enter + exit too long (\(frame)s)")) }
        }
        for (name, path) in def.sounds where !FileManager.default.fileExists(atPath: pack.directory.appending(path: path).path) {
            issues.append(.warning("sound '\(name)' file '\(path)' not found"))
        }
        return issues
    }
}

extension PackValidator {
    /// Seconds a standing step shows the frozen last frame of a non-looping animation (nil when under 0.12 s, or for
    /// single-frame poses and moving steps, where a held pose is intended).
    public static func frozenTail(_ step: StepDefinition, clips: ClipLibrary) -> Double? {
        guard step.motion.type == .none, case .success(let c) = clips.resolve(step.clip), !c.definition.loop,
              c.frames.count >= 2, c.definition.fps > 0 else { return nil }
        let hold = step.duration - Double(c.frames.count) / c.definition.fps
        return hold > 0.12 ? hold : nil
    }
}
