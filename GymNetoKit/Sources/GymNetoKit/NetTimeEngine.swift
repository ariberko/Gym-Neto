import Foundation

/// The brain of Gym Neto.
///
/// Feed it one `SensorSample` per second. It decides whether each second was
/// Work, Rest or Garbage, keeps running totals, builds a timeline and emits
/// events (for haptic nudges). It has no platform dependencies so the exact
/// same logic runs on Apple Watch, iPhone and in unit tests.
public final class NetTimeEngine {

    // MARK: Config
    public let kind: WorkoutKind
    public private(set) var profile: UserProfile
    private var model: EffortModel

    /// Seconds above the enter threshold needed to switch to work (filters single spikes).
    public var enterConfirmation: TimeInterval = 2
    /// Seconds below the exit threshold needed to leave work (a set has small pauses).
    public var exitConfirmation: TimeInterval = 6
    /// Seconds of still, screen-up posture before we call it screen time.
    public var screenTimeConfirmation: TimeInterval = 8
    /// One chart point every N seconds.
    public var pointInterval: TimeInterval = 5
    /// Gaps longer than this between samples are capped (eg. app was suspended).
    public var maxTick: TimeInterval = 5

    // MARK: Public state
    public let startDate: Date
    public private(set) var totals = Totals()
    public private(set) var state: ActivityState = .rest
    public private(set) var reason: GarbageReason?
    public private(set) var segments: [Segment] = []
    public private(set) var points: [TimelinePoint] = []
    public private(set) var sets = 0
    public private(set) var lastEffort: Double = 0
    public private(set) var lastHeartRate: Double?
    public private(set) var isPaused = false
    public private(set) var pausedTime: TimeInterval = 0
    public var calories: Double = 0

    /// Active seconds since start (pauses excluded).
    public var elapsed: TimeInterval { totals.total }

    // MARK: Private state
    private var lastTimestamp: Date?
    private var pauseStart: Date?
    private var aboveStreak: TimeInterval = 0
    private var belowStreak: TimeInterval = 0
    private var screenUpStreak: TimeInterval = 0
    private var offWorkStreak: TimeInterval = 0
    private var stateStart: TimeInterval = 0
    private var plannedRestRemaining: TimeInterval?
    private var plannedRestExpired = false
    private var nextNudgeAt: TimeInterval?
    private var nextPointAt: TimeInterval = 0
    private var heartHistory: [(t: TimeInterval, bpm: Double)] = []
    private var heartSum: Double = 0
    private var heartCount: Double = 0
    private var heartMax: Double?

    public init(kind: WorkoutKind, profile: UserProfile, startDate: Date) {
        self.kind = kind
        self.profile = profile
        self.model = EffortModel(kind: kind, profile: profile)
        self.startDate = startDate
        self.lastTimestamp = startDate
    }

    public func update(profile: UserProfile) {
        self.profile = profile
        self.model = EffortModel(kind: kind, profile: profile)
    }

    // MARK: Controls

    /// Start a manual rest timer (the "Rest" button). Rest beyond it becomes garbage.
    public func startPlannedRest(duration: TimeInterval? = nil) {
        plannedRestRemaining = duration ?? profile.plannedRestDuration
        plannedRestExpired = false
        offWorkStreak = 0
        // Leave "work" right away so the next set is detected with the normal enter rules.
        if profile.restMode == .allGarbage {
            if state != .garbage { transition(to: .garbage, reason: .longRest) }
        } else if state != .rest {
            transition(to: .rest, reason: nil)
        }
    }

    public func cancelPlannedRest() {
        plannedRestRemaining = nil
    }

    public func pause(at date: Date) {
        guard !isPaused else { return }
        isPaused = true
        pauseStart = date
    }

    public func resume(at date: Date) {
        guard isPaused else { return }
        if let p = pauseStart { pausedTime += max(0, date.timeIntervalSince(p)) }
        isPaused = false
        pauseStart = nil
        lastTimestamp = date
    }

    // MARK: Ingest

    @discardableResult
    public func ingest(_ sample: SensorSample) -> [EngineEvent] {
        guard !isPaused else { return [] }
        let raw = sample.timestamp.timeIntervalSince(lastTimestamp ?? startDate)
        lastTimestamp = sample.timestamp
        guard raw > 0 else { return [] }
        let dt = min(raw, maxTick)
        if raw > maxTick { pausedTime += raw - maxTick }

        let now = elapsed + dt
        var events: [EngineEvent] = []

        // Heart rate bookkeeping.
        if let hr = sample.heartRate {
            lastHeartRate = hr
            heartHistory.append((now, hr))
            heartHistory.removeAll { now - $0.t > 25 }
            heartSum += hr * dt
            heartCount += dt
            heartMax = max(heartMax ?? hr, hr)
        }

        let effort = model.effort(for: sample, heartTrend: heartTrend())
        lastEffort = effort

        // Hysteresis on the effort score.
        if effort >= model.enterThreshold { aboveStreak += dt } else { aboveStreak = 0 }
        if effort < model.exitThreshold { belowStreak += dt } else { belowStreak = 0 }

        if sample.posture == .screenUp, (sample.accelRMS ?? 0) < 0.04 {
            screenUpStreak += dt
        } else {
            screenUpStreak = 0
        }

        let strongBurst = effort >= model.enterThreshold + 0.2
        let wantsWork: Bool
        if sample.distracted {
            wantsWork = false
        } else if state == .work {
            wantsWork = belowStreak < exitConfirmation
        } else {
            wantsWork = aboveStreak >= enterConfirmation || strongBurst
        }

        // Planned rest timer.
        var inPlannedRest = false
        if var remaining = plannedRestRemaining {
            if wantsWork {
                plannedRestRemaining = nil // started the next set early - nice.
            } else {
                inPlannedRest = true
                remaining -= dt
                if remaining <= 0 {
                    plannedRestRemaining = nil
                    plannedRestExpired = true
                    events.append(.plannedRestFinished)
                    if profile.nudgeAfter > 0 { nextNudgeAt = elapsed + dt + profile.nudgeAfter }
                } else {
                    plannedRestRemaining = remaining
                }
            }
        }

        // Decide the state for this tick.
        let newState: ActivityState
        var newReason: GarbageReason?
        if wantsWork {
            newState = .work
            offWorkStreak = 0
            plannedRestExpired = false
        } else {
            offWorkStreak += dt
            if inPlannedRest {
                if profile.restMode == .allGarbage {
                    // The timer still paces you, but the user asked for every break to count as garbage.
                    newState = .garbage
                    newReason = garbageReason(for: sample, fallback: .longRest)
                } else {
                    newState = .rest
                }
            } else if plannedRestExpired {
                newState = .garbage
                newReason = garbageReason(for: sample, fallback: .restOverrun)
            } else if profile.restMode == .allowance && offWorkStreak <= profile.restAllowance {
                newState = .rest
            } else {
                newState = .garbage
                newReason = garbageReason(for: sample, fallback: .longRest)
            }
        }

        if newState != state || (newState == .garbage && newReason != reason) {
            if newState == .work && state != .work { sets += 1 }
            if newState != state {
                switch newState {
                case .work: events.append(.startedWork)
                case .rest: events.append(.startedRest)
                case .garbage:
                    events.append(.startedGarbage)
                    nextNudgeAt = profile.nudgeAfter > 0 ? now - dt + profile.nudgeAfter : nil
                }
            }
            transition(to: newState, reason: newReason, at: now - dt)
        }

        // Accumulate.
        switch newState {
        case .work: totals.work += dt
        case .rest: totals.rest += dt
        case .garbage:
            totals.garbage += dt
            if let r = newReason { totals.garbageByReason[r, default: 0] += dt }
        }
        extendCurrentSegment(to: now)

        // Nudges: first after `nudgeAfter`, then every minute.
        if newState == .garbage, let at = nextNudgeAt, now >= at {
            // No nudges while the user's own rest timer is running.
            if !inPlannedRest { events.append(.garbageNudge) }
            nextNudgeAt = at + 60
        }

        // Chart points.
        if now >= nextPointAt {
            points.append(TimelinePoint(offset: now, heartRate: sample.heartRate ?? lastHeartRate, effort: effort, state: newState))
            nextPointAt = now + pointInterval
        }
        return events
    }

    // MARK: Output

    public func snapshot() -> LiveSnapshot {
        LiveSnapshot(startDate: startDate,
                     kind: kind,
                     elapsed: elapsed,
                     totals: totals,
                     state: state,
                     reason: reason,
                     stateDuration: max(0, elapsed - stateStart),
                     plannedRestRemaining: plannedRestRemaining,
                     heartRate: lastHeartRate,
                     effort: lastEffort,
                     sets: sets,
                     calories: calories,
                     isPaused: isPaused)
    }

    public func finish(at endDate: Date, source: WorkoutSource) -> WorkoutRecord {
        WorkoutRecord(kind: kind,
                      source: source,
                      startDate: startDate,
                      endDate: endDate,
                      totals: totals,
                      pausedTime: pausedTime,
                      segments: segments,
                      points: points,
                      averageHeartRate: heartCount > 0 ? heartSum / heartCount : nil,
                      maxHeartRate: heartMax,
                      calories: calories,
                      sets: sets)
    }

    // MARK: Helpers

    /// bpm per second, least squares over the recent window.
    func heartTrend() -> Double? {
        guard heartHistory.count >= 3,
              let first = heartHistory.first, let last = heartHistory.last,
              last.t - first.t >= 6 else { return nil }
        let n = Double(heartHistory.count)
        let meanT = heartHistory.reduce(0) { $0 + $1.t } / n
        let meanB = heartHistory.reduce(0) { $0 + $1.bpm } / n
        var num = 0.0, den = 0.0
        for p in heartHistory {
            num += (p.t - meanT) * (p.bpm - meanB)
            den += (p.t - meanT) * (p.t - meanT)
        }
        return den > 0 ? num / den : nil
    }

    private func garbageReason(for sample: SensorSample, fallback: GarbageReason) -> GarbageReason {
        if sample.distracted || screenUpStreak >= screenTimeConfirmation { return .onPhone }
        if let c = sample.cadence, c >= 40, c < 120 { return .wandering }
        return fallback
    }

    private func transition(to newState: ActivityState, reason newReason: GarbageReason?, at time: TimeInterval? = nil) {
        let t = time ?? elapsed
        if newState != state { stateStart = t }
        state = newState
        reason = newReason
        if let last = segments.last, last.state == newState, last.reason == newReason, abs(last.end - t) < 0.001 {
            return
        }
        segments.append(Segment(state: newState, reason: newReason, start: t, end: t))
    }

    private func extendCurrentSegment(to time: TimeInterval) {
        if segments.isEmpty {
            segments.append(Segment(state: state, reason: reason, start: 0, end: time))
        } else {
            segments[segments.count - 1].end = time
        }
    }
}
