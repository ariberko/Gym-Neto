import Foundation
import GymNetoKit

/// Demo mode for screenshots and simulators (no sensors there).
/// Launch with `-demo -screen home|live|summary|settings` (watch: `start|live|summary`).
/// All data is produced by running fake sensor readings through the real NetTimeEngine.
enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    static var screen: String { UserDefaults.standard.string(forKey: "screen") ?? "home" }

    static var profile: UserProfile {
        var p = UserProfile.default
        p.restMode = .allowance
        p.restAllowance = 90
        return p
    }

    enum Phase {
        case work(Int), rest(Int), phone(Int), walk(Int), run(Int)
    }

    static let strengthPlan: [Phase] = [
        .walk(90), .work(40), .rest(80), .work(45), .rest(95), .work(40), .rest(70), .walk(150),
        .work(50), .rest(85), .work(45), .phone(240), .work(40), .rest(90), .work(45), .rest(60),
        .work(50), .rest(150), .work(45), .rest(75), .work(40), .phone(180), .work(45), .rest(80),
        .work(50), .rest(85), .work(45), .rest(70), .work(40), .walk(120), .work(50), .rest(90), .work(45)
    ]

    static let hiitPlan: [Phase] = Array(repeating: [Phase.work(40), .rest(20)], count: 22).flatMap { $0 } + [.rest(60)]
    static let runPlan: [Phase] = [.walk(120), .run(1500), .rest(100), .run(600), .walk(90)]
    static let boxingPlan: [Phase] = Array(repeating: [Phase.work(180), .rest(60)], count: 8).flatMap { $0 } + [.phone(200)]

    static func simulate(kind: WorkoutKind, start: Date, plan: [Phase]) -> NetTimeEngine {
        let engine = NetTimeEngine(kind: kind, profile: profile, startDate: start)
        var t: TimeInterval = 0
        var hr = 92.0
        for phase in plan {
            let (count, make): (Int, (Int) -> SensorSample) = {
                switch phase {
                case .work(let n):
                    return (n, { i in
                        hr = min(168, hr + 0.9)
                        return SensorSample(timestamp: start.addingTimeInterval(t), heartRate: hr,
                                            accelRMS: 0.2 + 0.06 * sin(Double(i)), rotationRMS: 1.3, cadence: 0, energyRate: 9.5)
                    })
                case .rest(let n), .phone(let n):
                    let screenUp: Bool = { if case .phone = phase { return true } else { return false } }()
                    return (n, { _ in
                        hr = max(96, hr - 0.55)
                        return SensorSample(timestamp: start.addingTimeInterval(t), heartRate: hr,
                                            accelRMS: 0.012, rotationRMS: 0.07, cadence: 0, energyRate: 2.4,
                                            posture: screenUp ? .screenUp : .other)
                    })
                case .walk(let n):
                    return (n, { _ in
                        hr = max(98, hr - 0.3)
                        return SensorSample(timestamp: start.addingTimeInterval(t), heartRate: hr,
                                            accelRMS: 0.03, rotationRMS: 0.2, cadence: 88, energyRate: 3.5)
                    })
                case .run(let n):
                    return (n, { i in
                        hr = min(162, hr + 0.4) + sin(Double(i) / 9)
                        return SensorSample(timestamp: start.addingTimeInterval(t), heartRate: hr,
                                            accelRMS: 0.09, rotationRMS: 0.6, cadence: 166, energyRate: 12)
                    })
                }
            }()
            for i in 0..<count {
                t += 1
                let sample = make(i)
                engine.calories += (sample.energyRate ?? 0) / 60
                engine.ingest(sample)
            }
        }
        return engine
    }

    private static func record(_ kind: WorkoutKind, daysAgo: Double, plan: [Phase], source: WorkoutSource = .watch) -> WorkoutRecord {
        let start = Date().addingTimeInterval(-daysAgo * 86_400 - 3_600)
        let engine = simulate(kind: kind, start: start, plan: plan)
        return engine.finish(at: start.addingTimeInterval(engine.elapsed), source: source)
    }

    static let history: [WorkoutRecord] = [
        record(.strength, daysAgo: 0, plan: strengthPlan),
        record(.hiit, daysAgo: 1, plan: hiitPlan),
        record(.running, daysAgo: 3, plan: runPlan),
        record(.strength, daysAgo: 4, plan: Array(strengthPlan.reversed())),
        record(.boxing, daysAgo: 6, plan: boxingPlan, source: .phone)
    ]

    /// A workout in progress: 13 phases in, 25 s into a set.
    static let liveSnapshot: LiveSnapshot = {
        let engine = simulate(kind: .strength, start: Date().addingTimeInterval(-1_500),
                              plan: Array(strengthPlan.prefix(13)) + [.work(25)])
        return engine.snapshot()
    }()
}
