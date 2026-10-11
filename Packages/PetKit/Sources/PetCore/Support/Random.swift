import Foundation

/// Injectable randomness so scheduler and selector tests are deterministic.
public protocol RandomSource: AnyObject {
    func next() -> UInt64
}

public extension RandomSource {
    /// Uniform in [0, 1).
    func unit() -> Double { Double(next() >> 11) * 0x1.0p-53 }

    func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * unit()
    }

    func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    func chance(_ p: Double) -> Bool { unit() < p }

    func element<T>(of array: [T]) -> T? {
        array.isEmpty ? nil : array[int(in: 0...(array.count - 1))]
    }

    /// Index picked proportionally to `weights`. Non-positive weights are never picked.
    func weightedIndex(_ weights: [Double]) -> Int? {
        let total = weights.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { return nil }
        var roll = unit() * total
        for (i, w) in weights.enumerated() where w > 0 {
            roll -= w
            if roll < 0 { return i }
        }
        return weights.lastIndex { $0 > 0 }
    }
}

/// SplitMix64: tiny, fast, good enough for gameplay randomness, and reproducible.
public final class SeededRandom: RandomSource {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public final class SystemRandom: RandomSource {
    private var generator = SystemRandomNumberGenerator()
    public init() {}
    public func next() -> UInt64 { generator.next() }
}

/// Injectable time source.
public protocol PetClock: AnyObject {
    var now: Date { get }
}

public final class SystemClock: PetClock {
    public init() {}
    public var now: Date { Date() }
}

public final class ManualClock: PetClock {
    public var now: Date
    public init(_ now: Date) { self.now = now }
    public func advance(_ seconds: TimeInterval) { now += seconds }
}
