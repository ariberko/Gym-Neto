import Foundation

// MARK: - Activity state

/// The three buckets every second of a workout falls into.
public enum ActivityState: String, Codable, Sendable, CaseIterable {
    /// You are actually training (reps, intervals, running...).
    case work
    /// Healthy rest: a planned rest timer, or a short break between sets inside your rest allowance.
    case rest
    /// Garbage time: rest that ran too long, phone scrolling, wandering around.
    case garbage

    public var title: String {
        switch self {
        case .work: return "Work"
        case .rest: return "Rest"
        case .garbage: return "Garbage"
        }
    }
}

/// Why a stretch of time was classified as garbage.
public enum GarbageReason: String, Codable, Sendable, CaseIterable {
    /// Rest between sets went past your rest allowance.
    case longRest
    /// A planned rest timer ran out and you still did not start.
    case restOverrun
    /// Wrist raised and still, screen facing up, or phone app switching - classic scrolling posture.
    case onPhone
    /// Walking around at a slow pace without effort (chatting, looking for equipment...).
    case wandering

    public var title: String {
        switch self {
        case .longRest: return "Long rests"
        case .restOverrun: return "Rest timer overrun"
        case .onPhone: return "Screen time"
        case .wandering: return "Wandering around"
        }
    }

    public var symbol: String {
        switch self {
        case .longRest: return "hourglass"
        case .restOverrun: return "timer"
        case .onPhone: return "iphone"
        case .wandering: return "figure.walk"
        }
    }
}

/// Coarse wrist / device posture derived from the gravity vector.
public enum DevicePosture: String, Codable, Sendable {
    /// Screen facing the user, device held still (looking at a phone or the watch).
    case screenUp
    /// Anything else.
    case other
}

// MARK: - Workout kinds

/// Workout categories. Each one weighs the sensors differently.
public enum WorkoutKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case strength
    case functional
    case hiit
    case cardio
    case running

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .strength: return "Strength"
        case .functional: return "Functional"
        case .hiit: return "HIIT"
        case .cardio: return "Cardio"
        case .running: return "Running"
        }
    }

    public var symbol: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .functional: return "figure.cross.training"
        case .hiit: return "bolt.heart.fill"
        case .cardio: return "figure.elliptical"
        case .running: return "figure.run"
        }
    }

    /// Steady-state workouts (running, cardio) rely more on heart rate and cadence than on bursts of motion.
    public var isSteadyState: Bool {
        self == .cardio || self == .running
    }
}

// MARK: - Sensor sample

/// One fused reading, produced about once per second from Apple Watch / iPhone sensors.
public struct SensorSample: Codable, Sendable, Equatable {
    public var timestamp: Date
    /// Beats per minute (HealthKit live heart rate).
    public var heartRate: Double?
    /// RMS of user acceleration magnitude over the last ~2 s, in g (gravity removed).
    public var accelRMS: Double?
    /// RMS of rotation rate magnitude over the last ~2 s, in rad/s.
    public var rotationRMS: Double?
    /// Steps per minute (CMPedometer current cadence).
    public var cadence: Double?
    /// Active energy burn rate, kcal per minute (HealthKit active energy).
    public var energyRate: Double?
    /// Device posture from the gravity vector.
    public var posture: DevicePosture?
    /// True when we know for sure the user is distracted (eg. iPhone app switched to another app while unlocked).
    public var distracted: Bool

    public init(timestamp: Date,
                heartRate: Double? = nil,
                accelRMS: Double? = nil,
                rotationRMS: Double? = nil,
                cadence: Double? = nil,
                energyRate: Double? = nil,
                posture: DevicePosture? = nil,
                distracted: Bool = false) {
        self.timestamp = timestamp
        self.heartRate = heartRate
        self.accelRMS = accelRMS
        self.rotationRMS = rotationRMS
        self.cadence = cadence
        self.energyRate = energyRate
        self.posture = posture
        self.distracted = distracted
    }
}

// MARK: - User profile / settings

public struct UserProfile: Codable, Sendable, Equatable {
    /// Resting heart rate (auto-filled from Apple Health when available).
    public var restingHeartRate: Double
    /// Max heart rate (auto-filled from date of birth when available: 208 - 0.7 * age).
    public var maxHeartRate: Double
    /// When true, short breaks between sets count as Rest instead of Garbage.
    public var autoRestEnabled: Bool
    /// How long a single break can last before it turns into Garbage time.
    public var restAllowance: TimeInterval
    /// Default length of the manual rest timer.
    public var plannedRestDuration: TimeInterval
    /// Haptic nudge after this many seconds of garbage time (0 disables nudges).
    public var nudgeAfter: TimeInterval
    /// 0 = relaxed (easier to count as work), 1 = strict.
    public var strictness: Double

    public init(restingHeartRate: Double = 62,
                maxHeartRate: Double = 188,
                autoRestEnabled: Bool = true,
                restAllowance: TimeInterval = 90,
                plannedRestDuration: TimeInterval = 90,
                nudgeAfter: TimeInterval = 30,
                strictness: Double = 0.5) {
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
        self.autoRestEnabled = autoRestEnabled
        self.restAllowance = restAllowance
        self.plannedRestDuration = plannedRestDuration
        self.nudgeAfter = nudgeAfter
        self.strictness = strictness
    }

    public static let `default` = UserProfile()

    /// Tanaka-style estimate, a bit more accurate than 220 - age.
    public static func estimatedMaxHeartRate(age: Int) -> Double {
        208 - 0.7 * Double(age)
    }
}

// MARK: - Timeline

/// A continuous stretch of one state.
public struct Segment: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var state: ActivityState
    public var reason: GarbageReason?
    /// Seconds since workout start (active time, pauses excluded).
    public var start: TimeInterval
    public var end: TimeInterval

    public init(id: UUID = UUID(), state: ActivityState, reason: GarbageReason?, start: TimeInterval, end: TimeInterval) {
        self.id = id
        self.state = state
        self.reason = reason
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end - start }
}

/// A downsampled point for charts (one every few seconds).
public struct TimelinePoint: Codable, Sendable, Equatable, Identifiable {
    public var offset: TimeInterval
    public var heartRate: Double?
    public var effort: Double
    public var state: ActivityState

    public var id: TimeInterval { offset }

    public init(offset: TimeInterval, heartRate: Double?, effort: Double, state: ActivityState) {
        self.offset = offset
        self.heartRate = heartRate
        self.effort = effort
        self.state = state
    }
}

// MARK: - Totals & live snapshot

public struct Totals: Codable, Sendable, Equatable {
    public var work: TimeInterval = 0
    public var rest: TimeInterval = 0
    public var garbage: TimeInterval = 0
    public var garbageByReason: [GarbageReason: TimeInterval] = [:]

    public init() {}

    public var total: TimeInterval { work + rest + garbage }

    /// Share of the workout that was real work, 0...1.
    public var netRatio: Double { total > 0 ? work / total : 0 }

    /// Share of the workout that was work or healthy rest, 0...1.
    public var focusRatio: Double { total > 0 ? (work + rest) / total : 0 }

    public subscript(state: ActivityState) -> TimeInterval {
        switch state {
        case .work: return work
        case .rest: return rest
        case .garbage: return garbage
        }
    }
}

/// Events the UI should react to (haptics, banners).
public enum EngineEvent: String, Codable, Sendable {
    case startedWork
    case startedRest
    case startedGarbage
    case garbageNudge
    case plannedRestFinished
}

/// What the live screens render.
public struct LiveSnapshot: Codable, Sendable, Equatable {
    public var startDate: Date
    public var kind: WorkoutKind
    public var elapsed: TimeInterval
    public var totals: Totals
    public var state: ActivityState
    public var reason: GarbageReason?
    /// Seconds spent in the current state.
    public var stateDuration: TimeInterval
    /// Seconds remaining on the planned rest timer, if running.
    public var plannedRestRemaining: TimeInterval?
    public var heartRate: Double?
    public var effort: Double
    public var sets: Int
    public var calories: Double
    public var isPaused: Bool

    public init(startDate: Date, kind: WorkoutKind, elapsed: TimeInterval, totals: Totals, state: ActivityState,
                reason: GarbageReason?, stateDuration: TimeInterval, plannedRestRemaining: TimeInterval?,
                heartRate: Double?, effort: Double, sets: Int, calories: Double, isPaused: Bool) {
        self.startDate = startDate
        self.kind = kind
        self.elapsed = elapsed
        self.totals = totals
        self.state = state
        self.reason = reason
        self.stateDuration = stateDuration
        self.plannedRestRemaining = plannedRestRemaining
        self.heartRate = heartRate
        self.effort = effort
        self.sets = sets
        self.calories = calories
        self.isPaused = isPaused
    }
}

// MARK: - Finished workout

public enum WorkoutSource: String, Codable, Sendable {
    case watch
    case phone
}

public struct WorkoutRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var kind: WorkoutKind
    public var source: WorkoutSource
    public var startDate: Date
    public var endDate: Date
    public var totals: Totals
    public var pausedTime: TimeInterval
    public var segments: [Segment]
    public var points: [TimelinePoint]
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var calories: Double
    /// Number of work bouts (roughly: sets / intervals).
    public var sets: Int

    public init(id: UUID = UUID(), kind: WorkoutKind, source: WorkoutSource, startDate: Date, endDate: Date,
                totals: Totals, pausedTime: TimeInterval, segments: [Segment], points: [TimelinePoint],
                averageHeartRate: Double?, maxHeartRate: Double?, calories: Double, sets: Int) {
        self.id = id
        self.kind = kind
        self.source = source
        self.startDate = startDate
        self.endDate = endDate
        self.totals = totals
        self.pausedTime = pausedTime
        self.segments = segments
        self.points = points
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.calories = calories
        self.sets = sets
    }

    /// 0...100 score: work share, plus a small bonus for healthy (in-allowance) rest.
    public var netScore: Int {
        guard totals.total > 0 else { return 0 }
        let score = (totals.work + 0.35 * totals.rest) / totals.total
        return Int((min(1, score / 0.8) * 100).rounded())
    }

    public var grade: String {
        switch netScore {
        case 90...: return "A+"
        case 80..<90: return "A"
        case 70..<80: return "B"
        case 60..<70: return "C"
        case 45..<60: return "D"
        default: return "F"
        }
    }

    public var longestGarbage: TimeInterval {
        segments.filter { $0.state == .garbage }.map(\.duration).max() ?? 0
    }
}
