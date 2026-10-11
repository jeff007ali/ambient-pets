import AppKit
import PetCore
import QuartzCore

/// Renderer interface, so vector / video / 3D renderers can come later behind the same API.
@MainActor
public protocol PetRenderer: AnyObject {
    var facing: Facing { get set }
    func play(_ clip: ResolvedClip)
    func advance(by dt: Double)
    func teardown()
}

/// CALayer sprite renderer: nearest-neighbour scaled frames aligned on their pivot, mirrored for facing.
///
/// Layer tree (all origins at the pivot, y up):
/// ```
/// container      position = pivot in window; squash / fade apply here
/// └ swingLayer   screen-space rotation from the motion (pendulum swing)
/// └ facingLayer  scaleX ±1 for facing; effects that should mirror live in tiltLayer
///   └ leanLayer  the clip's own lean (e.g. an upright pose tilted forward for flight)
///     └ tiltLayer  tilt effect
///       └ spriteLayer
/// overlay        not mirrored: speech bubble
/// ```
@MainActor
public final class SpriteRenderer: PetRenderer {
    let pack: LoadedPack
    /// Native sprite px → points.
    let scale: Double

    let container = CALayer()
    let swingLayer = CALayer()
    let facingLayer = CALayer()
    let leanLayer = CALayer()
    let tiltLayer = CALayer()
    let spriteLayer = CALayer()
    let overlay = CALayer()

    private(set) var clip: ResolvedClip?
    private var clipElapsed = 0.0
    private var shownFrame: String?

    public var facing: Facing = .right {
        didSet { applyFacing() }
    }

    public init(pack: LoadedPack, scale: Double, pivot: CGPoint, in root: CALayer) {
        self.pack = pack
        self.scale = scale
        for layer in [container, swingLayer, facingLayer, leanLayer, tiltLayer, spriteLayer, overlay] {
            layer.actions = noImplicitActions()
            layer.bounds = .zero
            layer.anchorPoint = .zero
        }
        container.position = pivot
        overlay.position = pivot
        spriteLayer.magnificationFilter = .nearest
        spriteLayer.minificationFilter = .linear
        spriteLayer.contentsGravity = .resize
        root.addSublayer(container)
        container.addSublayer(swingLayer)
        swingLayer.addSublayer(facingLayer)
        facingLayer.addSublayer(leanLayer)
        leanLayer.addSublayer(tiltLayer)
        tiltLayer.addSublayer(spriteLayer)
        root.addSublayer(overlay)
    }

    public func play(_ clip: ResolvedClip) {
        self.clip = clip
        clipElapsed = 0
        applyFacing()
        applyLean(clip.definition.lean ?? 0)
        show(clip.frameName(at: 0))
    }

    private var swingAngle = 0.0

    /// Screen-space body rotation (counter-clockwise radians), set every tick while swinging. When the motion
    /// stops swinging (`angle == nil`), the body eases back upright instead of snapping.
    func setSwing(_ angle: Double?, dt: Double) {
        swingAngle = angle ?? swingAngle * exp(-dt * 14)
        if abs(swingAngle) < 0.001 { swingAngle = 0 }
        swingLayer.transform = CATransform3DMakeRotation(swingAngle, 0, 0, 1)
    }

    /// Forward lean in degrees. Art-native space: forward is +x for right-facing art, -x for left-facing art.
    private func applyLean(_ degrees: Double) {
        let t = CATransform3DMakeRotation(-degrees * .pi / 180 * pack.data.atlas.facing.sign, 0, 0, 1)
        guard !CATransform3DEqualToTransform(t, leanLayer.transform) else { return }
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = NSValue(caTransform3D: leanLayer.presentation()?.transform ?? leanLayer.transform)
        a.toValue = NSValue(caTransform3D: t)
        a.duration = 0.18
        leanLayer.transform = t
        leanLayer.add(a, forKey: "lean")
    }

    public func advance(by dt: Double) {
        guard let clip else { return }
        clipElapsed += dt
        show(clip.frameName(at: clipElapsed))
    }

    public func teardown() {
        container.removeAllAnimations()
        container.removeFromSuperlayer()
        overlay.removeFromSuperlayer()
    }

    /// Extents of the frame currently shown, in points, y up from the pivot.
    var currentExtents: SpriteExtents {
        guard let name = shownFrame, let f = pack.geometry[name] else { return .zero }
        return f.extents.scaled(scale)
    }

    /// A clip attachment point in points relative to the pivot, in the art's native (unmirrored) orientation.
    func point(_ name: String, default fallback: CGPoint) -> CGPoint {
        let p = clip?.point(name) ?? fallback
        return CGPoint(x: p.x * scale, y: p.y * scale)
    }

    private func show(_ name: String) {
        guard name != shownFrame, let f = pack.frames[name] else { return }
        shownFrame = name
        let s = scale
        spriteLayer.contents = f.image
        spriteLayer.frame = CGRect(x: -f.frame.pivot.x * s, y: -(f.frame.rect.height - f.frame.pivot.y) * s,
                                   width: f.frame.rect.width * s, height: f.frame.rect.height * s)
    }

    private func applyFacing() {
        let mirror = (clip?.definition.mirrorForLeft ?? true) && facing != pack.data.atlas.facing
        facingLayer.transform = mirror ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
    }
}
