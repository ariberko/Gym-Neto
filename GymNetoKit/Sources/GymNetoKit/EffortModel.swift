import Foundation

/// Turns raw sensor values into a single 0...1 "effort" score.
///
/// Each available signal gives a 0...1 sub-score. Missing signals are skipped
/// and the remaining weights are re-normalized, so the model works with only a
/// watch, only a phone, or both.
public struct EffortModel: Sendable {

    public struct Weights: Sendable {
        public var motion: Double
        public var rotation: Double
        public var heartLevel: Double
        public var heartTrend: Double
        public var energy: Double
        public var cadence: Double
    }

    public let kind: WorkoutKind
    public let profile: UserProfile

    public init(kind: WorkoutKind, profile: UserProfile) {
        self.kind = kind
        self.profile = profile
    }

    public var weights: Weights {
        switch kind {
        case .strength:
            // Lifting = short bursts of wrist motion. HR stays high while resting, so the
            // *trend* (rising vs. recovering) matters more than the level.
            return Weights(motion: 0.40, rotation: 0.15, heartLevel: 0.10, heartTrend: 0.20, energy: 0.10, cadence: 0.05)
        case .functional, .hiit:
            return Weights(motion: 0.35, rotation: 0.15, heartLevel: 0.15, heartTrend: 0.15, energy: 0.10, cadence: 0.10)
        case .cardio:
            return Weights(motion: 0.20, rotation: 0.05, heartLevel: 0.35, heartTrend: 0.05, energy: 0.15, cadence: 0.20)
        case .running:
            return Weights(motion: 0.15, rotation: 0.05, heartLevel: 0.25, heartTrend: 0.05, energy: 0.15, cadence: 0.35)
        case .cycling:
            // Wrist barely moves and there are no steps: heart + energy do the work.
            return Weights(motion: 0.10, rotation: 0.05, heartLevel: 0.45, heartTrend: 0.10, energy: 0.30, cadence: 0)
        case .rowing:
            return Weights(motion: 0.30, rotation: 0.15, heartLevel: 0.30, heartTrend: 0.05, energy: 0.20, cadence: 0)
        case .boxing:
            // Punches = big wrist acceleration and rotation.
            return Weights(motion: 0.40, rotation: 0.25, heartLevel: 0.10, heartTrend: 0.10, energy: 0.10, cadence: 0.05)
        }
    }

    /// - Parameter heartTrend: bpm per second over the last ~20 s (positive = rising).
    public func effort(for sample: SensorSample, heartTrend: Double?) -> Double {
        let w = weights
        var parts: [(score: Double, weight: Double)] = []

        if let a = sample.accelRMS {
            parts.append((ramp(a, from: 0.025, to: 0.18), w.motion))
        }
        if let r = sample.rotationRMS {
            parts.append((ramp(r, from: 0.20, to: 1.6), w.rotation))
        }
        if let hr = sample.heartRate {
            let reserve = (hr - profile.restingHeartRate) / max(1, profile.maxHeartRate - profile.restingHeartRate)
            let low = kind.isSteadyState ? 0.40 : 0.30
            parts.append((ramp(reserve, from: low, to: 0.75), w.heartLevel))
        }
        if let trend = heartTrend {
            // Falling fast (recovering) -> 0, flat -> ~0.25, rising -> 1.
            parts.append((ramp(trend, from: -0.25, to: 0.6), w.heartTrend))
        }
        if let e = sample.energyRate {
            parts.append((ramp(e, from: 3, to: 11), w.energy))
        }
        if let c = sample.cadence, w.cadence > 0 {
            let start = kind.isSteadyState ? 60.0 : 90.0
            parts.append((ramp(c, from: start, to: 150), w.cadence))
        }

        let totalWeight = parts.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        var score = parts.reduce(0) { $0 + $1.score * $1.weight } / totalWeight

        // Strong motion alone is enough to call it work (a heavy set barely moves HR at first).
        if let a = sample.accelRMS, !kind.isSteadyState {
            score = max(score, ramp(a, from: 0.08, to: 0.30))
        }
        // Clear running cadence alone is enough for steady-state workouts.
        if let c = sample.cadence, kind == .running || kind == .cardio {
            score = max(score, ramp(c, from: 120, to: 160))
        }
        return min(1, max(0, score))
    }

    /// Thresholds shift with strictness: strict users need more effort to count as work.
    public var enterThreshold: Double { 0.40 + 0.15 * profile.strictness }
    public var exitThreshold: Double { 0.22 + 0.12 * profile.strictness }
}

/// Linear ramp: 0 at `from`, 1 at `to`, clamped.
@inline(__always)
func ramp(_ value: Double, from: Double, to: Double) -> Double {
    guard to != from else { return value >= to ? 1 : 0 }
    return min(1, max(0, (value - from) / (to - from)))
}
