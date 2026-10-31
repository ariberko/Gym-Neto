import Foundation

/// A short, human tip shown on the summary screen.
public struct Insight: Identifiable, Sendable, Equatable {
    public enum Tone: Sendable { case good, warning, info }
    public var id: String { title }
    public var symbol: String
    public var title: String
    public var detail: String
    public var tone: Tone
}

public enum InsightBuilder {

    /// Builds coaching tips from a finished (or running) workout.
    public static func insights(for record: WorkoutRecord, profile: UserProfile, history: [WorkoutRecord] = []) -> [Insight] {
        var out: [Insight] = []
        let t = record.totals
        guard t.total >= 60 else { return out }

        // 1. Net ratio verdict.
        let pct = Int((t.netRatio * 100).rounded())
        if t.netRatio >= 0.6 {
            out.append(Insight(symbol: "flame.fill", title: "Laser focused",
                               detail: "\(pct)% of your session was real work. Great job.", tone: .good))
        } else if t.netRatio < 0.35 {
            out.append(Insight(symbol: "exclamationmark.triangle.fill", title: "Mostly downtime",
                               detail: "Only \(pct)% was real work. Try supersets or a rest timer.", tone: .warning))
        }

        // 2. Biggest garbage source.
        if let top = t.garbageByReason.max(by: { $0.value < $1.value }), top.value >= 60 {
            let reason = top.key, seconds = top.value
            let text: String
            switch reason {
            case .onPhone: text = "You lost \(Format.minutes(seconds)) looking at a screen. Leave the phone in the locker."
            case .longRest: text = "Rests past \(Format.clock(profile.restAllowance)) cost you \(Format.minutes(seconds))."
            case .restOverrun: text = "You ran past your rest timer for \(Format.minutes(seconds)) total."
            case .wandering: text = "\(Format.minutes(seconds)) walking around. Plan your next machine before you finish a set."
            }
            out.append(Insight(symbol: reason.symbol, title: "Top time thief: \(reason.title)", detail: text, tone: .warning))
        }

        // 3. Average break length.
        let breaks = mergedBreaks(record.segments)
        if breaks.count >= 2 && profile.restMode == .allowance {
            let avg = breaks.reduce(0, +) / Double(breaks.count)
            let tone: Insight.Tone = avg <= profile.restAllowance ? .good : .warning
            out.append(Insight(symbol: "pause.circle.fill", title: "Average break \(Format.clock(avg))",
                               detail: avg <= profile.restAllowance
                                ? "Right on your \(Format.clock(profile.restAllowance)) target."
                                : "That is \(Format.clock(avg - profile.restAllowance)) over your target.",
                               tone: tone))
        }

        if breaks.count >= 2 && profile.restMode != .allowance {
            let avg = breaks.reduce(0, +) / Double(breaks.count)
            out.append(Insight(symbol: "pause.circle.fill", title: "Average break \(Format.clock(avg))",
                               detail: "Every break counts as garbage in your rest mode. Shorter breaks = higher score.",
                               tone: avg <= 60 ? .good : .info))
        }

        // 4. Compare to recent workouts of the same kind.
        let past = history.filter { $0.kind == record.kind && $0.id != record.id && $0.startDate < record.startDate }.prefix(5)
        if past.count >= 2 {
            let avgRatio = past.map(\.totals.netRatio).reduce(0, +) / Double(past.count)
            let diff = Int(((t.netRatio - avgRatio) * 100).rounded())
            if diff >= 3 {
                out.append(Insight(symbol: "arrow.up.right.circle.fill", title: "Up \(diff) points",
                                   detail: "More focused than your last \(past.count) \(record.kind.title.lowercased()) sessions.", tone: .good))
            } else if diff <= -3 {
                out.append(Insight(symbol: "arrow.down.right.circle.fill", title: "Down \(-diff) points",
                                   detail: "Less focused than your last \(past.count) \(record.kind.title.lowercased()) sessions.", tone: .warning))
            }
        }

        // 5. Potential time saved.
        if t.garbage >= 120 {
            out.append(Insight(symbol: "clock.arrow.circlepath", title: "Same workout, \(Format.minutes(t.garbage)) shorter",
                               detail: "Cut the garbage time and you would finish in \(Format.minutes(t.work + t.rest)).", tone: .info))
        }
        return out
    }

    /// Lengths of every off-work stretch (rest + garbage glued together).
    public static func mergedBreaks(_ segments: [Segment]) -> [TimeInterval] {
        var result: [TimeInterval] = []
        var current: TimeInterval = 0
        for s in segments {
            if s.state == .work {
                if current > 0 { result.append(current) }
                current = 0
            } else {
                current += s.duration
            }
        }
        // The last break (after the final set) is not a "between sets" break.
        return result.filter { $0 >= 5 }
    }
}
