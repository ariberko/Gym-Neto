import Foundation

/// Tiny summary for the watch face complication and the iPhone Live Activity.
///
/// Widgets cannot refresh every second, so while you are working we hand them
/// `liveWorkStart` (now - net time) and let the system count up from it with a
/// timer text. When you stop working the number freezes until the next update.
public struct NetGlance: Codable, Sendable, Equatable, Hashable {
    public var isLive: Bool
    public var isPaused: Bool = false
    public var kind: WorkoutKind?
    public var state: ActivityState?
    public var reason: GarbageReason?
    public var work: TimeInterval
    public var rest: TimeInterval
    public var garbage: TimeInterval
    public var updatedAt: Date
    public var restEndsAt: Date?
    public var heartRate: Int?
    // Today (shown when no workout is running).
    public var todayWork: TimeInterval
    public var todayTotal: TimeInterval
    public var lastGrade: String?
    public var lastScore: Int?

    public init(isLive: Bool = false, kind: WorkoutKind? = nil, state: ActivityState? = nil, reason: GarbageReason? = nil,
                work: TimeInterval = 0, rest: TimeInterval = 0, garbage: TimeInterval = 0, updatedAt: Date = Date(),
                restEndsAt: Date? = nil, heartRate: Int? = nil, todayWork: TimeInterval = 0, todayTotal: TimeInterval = 0,
                lastGrade: String? = nil, lastScore: Int? = nil) {
        self.isLive = isLive
        self.kind = kind
        self.state = state
        self.reason = reason
        self.work = work
        self.rest = rest
        self.garbage = garbage
        self.updatedAt = updatedAt
        self.restEndsAt = restEndsAt
        self.heartRate = heartRate
        self.todayWork = todayWork
        self.todayTotal = todayTotal
        self.lastGrade = lastGrade
        self.lastScore = lastScore
    }

    public init(snapshot s: LiveSnapshot, at date: Date = Date()) {
        self.init(isLive: true, kind: s.kind, state: s.state, reason: s.reason,
                  work: s.totals.work, rest: s.totals.rest, garbage: s.totals.garbage, updatedAt: date,
                  restEndsAt: s.plannedRestRemaining.map { date.addingTimeInterval($0) },
                  heartRate: s.heartRate.map { Int($0) })
        self.isPaused = s.isPaused
    }

    public var total: TimeInterval { work + rest + garbage }
    public var netRatio: Double { total > 0 ? work / total : 0 }

    /// Start date for a counting-up timer showing net time, only while working.
    public var liveWorkStart: Date? {
        guard isLive, !isPaused, state == .work else { return nil }
        return updatedAt.addingTimeInterval(-work)
    }

    /// Start date for a counting-up timer showing total time while live.
    public var liveTotalStart: Date? {
        isLive && !isPaused ? updatedAt.addingTimeInterval(-total) : nil
    }

    /// Adds a finished workout to "today" and leaves live mode.
    public func finishing(_ record: WorkoutRecord, calendar: Calendar = .current) -> NetGlance {
        var g = NetGlance()
        let sameDay = calendar.isDate(updatedAt, inSameDayAs: record.endDate)
        g.todayWork = (sameDay ? todayWork : 0) + record.totals.work
        g.todayTotal = (sameDay ? todayTotal : 0) + record.totals.total
        g.lastGrade = record.grade
        g.lastScore = record.netScore
        g.updatedAt = record.endDate
        g.kind = record.kind
        g.work = record.totals.work
        g.rest = record.totals.rest
        g.garbage = record.totals.garbage
        return g
    }

    /// Keeps today's numbers, switches live data on.
    public func merging(live snapshot: LiveSnapshot, at date: Date = Date()) -> NetGlance {
        var g = NetGlance(snapshot: snapshot, at: date)
        let today = todayValues(now: date)
        g.todayWork = today.work
        g.todayTotal = today.total
        g.lastGrade = lastGrade
        g.lastScore = lastScore
        return g
    }

    /// Today's numbers reset at midnight.
    public func todayValues(now: Date = Date(), calendar: Calendar = .current) -> (work: TimeInterval, total: TimeInterval) {
        calendar.isDate(updatedAt, inSameDayAs: now) ? (todayWork, todayTotal) : (0, 0)
    }
}
