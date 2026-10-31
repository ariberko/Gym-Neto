import XCTest
@testable import GymNetoKit

final class NetTimeEngineTests: XCTestCase {

    let start = Date(timeIntervalSince1970: 1_000_000)

    private func lifting(_ t: Int, hr: Double = 130) -> SensorSample {
        SensorSample(timestamp: start.addingTimeInterval(TimeInterval(t)), heartRate: hr,
                     accelRMS: 0.22, rotationRMS: 1.4, cadence: 0, energyRate: 9)
    }

    private func sitting(_ t: Int, hr: Double = 110, posture: DevicePosture = .other, cadence: Double = 0) -> SensorSample {
        SensorSample(timestamp: start.addingTimeInterval(TimeInterval(t)), heartRate: hr,
                     accelRMS: 0.01, rotationRMS: 0.05, cadence: cadence, energyRate: 2, posture: posture)
    }

    private func run(_ engine: NetTimeEngine, from: Int, to: Int, _ make: (Int) -> SensorSample) -> [EngineEvent] {
        var events: [EngineEvent] = []
        for t in from..<to { events += engine.ingest(make(t + 1)) }
        return events
    }

    func testLiftingCountsAsWork() {
        let engine = NetTimeEngine(kind: .strength, profile: .default, startDate: start)
        _ = run(engine, from: 0, to: 40) { lifting($0) }
        XCTAssertEqual(engine.state, .work)
        XCTAssertGreaterThan(engine.totals.work, 35)
        XCTAssertEqual(engine.sets, 1)
    }

    func testShortBreakIsRestAndLongBreakIsGarbage() {
        var profile = UserProfile.default
        profile.restMode = .allowance
        profile.restAllowance = 60
        let engine = NetTimeEngine(kind: .strength, profile: profile, startDate: start)
        _ = run(engine, from: 0, to: 30) { lifting($0) }
        let events = run(engine, from: 30, to: 150) { sitting($0) }

        XCTAssertEqual(engine.state, .garbage)
        XCTAssertEqual(engine.reason, .longRest)
        XCTAssertTrue(events.contains(.startedRest))
        XCTAssertTrue(events.contains(.startedGarbage))
        XCTAssertTrue(events.contains(.garbageNudge))
        // ~6 s exit lag counts as work, then 60 s rest, the rest is garbage.
        XCTAssertEqual(engine.totals.rest, 60, accuracy: 1)
        XCTAssertEqual(engine.totals.garbage, 120 - 60 - engine.exitConfirmation, accuracy: 1.5)
        XCTAssertEqual(engine.totals.total, 150, accuracy: 0.001)
    }

    func testDefaultModeMakesEveryBreakGarbage() {
        XCTAssertEqual(UserProfile.default.restMode, .allGarbage)
        let engine = NetTimeEngine(kind: .strength, profile: .default, startDate: start)
        _ = run(engine, from: 0, to: 20) { lifting($0) }
        _ = run(engine, from: 20, to: 60) { sitting($0) }
        XCTAssertEqual(engine.totals.rest, 0)
        XCTAssertGreaterThan(engine.totals.garbage, 30)
    }

    func testPlannedRestThenOverrun() {
        var profile = UserProfile.default
        profile.restMode = .timerOnly
        let engine = NetTimeEngine(kind: .strength, profile: profile, startDate: start)
        _ = run(engine, from: 0, to: 20) { lifting($0) }
        engine.startPlannedRest(duration: 30)
        let events = run(engine, from: 20, to: 80) { sitting($0) }
        XCTAssertTrue(events.contains(.plannedRestFinished))
        XCTAssertEqual(engine.state, .garbage)
        XCTAssertEqual(engine.reason, .restOverrun)
        XCTAssertEqual(engine.totals.rest, 30, accuracy: 1)
    }

    func testScreenPostureIsTaggedAsScreenTime() {
        var profile = UserProfile.default
        profile.restMode = .allowance
        profile.restAllowance = 10
        let engine = NetTimeEngine(kind: .strength, profile: profile, startDate: start)
        _ = run(engine, from: 0, to: 20) { lifting($0) }
        _ = run(engine, from: 20, to: 80) { sitting($0, posture: .screenUp) }
        XCTAssertEqual(engine.reason, .onPhone)
        XCTAssertGreaterThan(engine.totals.garbageByReason[.onPhone] ?? 0, 30)
    }

    func testSlowWalkingIsWandering() {
        var profile = UserProfile.default
        profile.restAllowance = 10
        let engine = NetTimeEngine(kind: .strength, profile: profile, startDate: start)
        _ = run(engine, from: 0, to: 60) { sitting($0, hr: 90, cadence: 80) }
        XCTAssertEqual(engine.reason, .wandering)
    }

    func testTimerOnlyModeBreakWithoutTimerIsGarbage() {
        var profile = UserProfile.default
        profile.restMode = .timerOnly
        let engine = NetTimeEngine(kind: .strength, profile: profile, startDate: start)
        _ = run(engine, from: 0, to: 20) { lifting($0) }
        _ = run(engine, from: 20, to: 60) { sitting($0) }
        XCTAssertEqual(engine.totals.rest, 0)
        XCTAssertEqual(engine.state, .garbage)
    }

    func testAllGarbageModeTimerIsGarbageButNoNudge() {
        var profile = UserProfile.default
        profile.nudgeAfter = 10
        let engine = NetTimeEngine(kind: .strength, profile: profile, startDate: start)
        _ = run(engine, from: 0, to: 20) { lifting($0) }
        engine.startPlannedRest(duration: 40)
        let during = run(engine, from: 20, to: 59) { sitting($0) }
        XCTAssertFalse(during.contains(.garbageNudge))
        XCTAssertEqual(engine.totals.rest, 0)
        XCTAssertEqual(engine.totals.garbage, 39, accuracy: 0.001)

        let after = run(engine, from: 59, to: 80) { sitting($0) }
        XCTAssertTrue(after.contains(.plannedRestFinished))
        XCTAssertTrue(after.contains(.garbageNudge))
        XCTAssertEqual(engine.reason, .restOverrun)
    }

    func testGlanceCountsUpOnlyWhileWorking() throws {
        let engine = NetTimeEngine(kind: .boxing, profile: .default, startDate: start)
        _ = run(engine, from: 0, to: 30) { lifting($0) }
        let now = start.addingTimeInterval(30)
        let glance = NetGlance(snapshot: engine.snapshot(), at: now)
        XCTAssertTrue(glance.isLive)
        let workStart = try XCTUnwrap(glance.liveWorkStart)
        XCTAssertEqual(now.timeIntervalSince(workStart), engine.totals.work, accuracy: 0.001)

        _ = run(engine, from: 30, to: 60) { sitting($0) }
        XCTAssertNil(NetGlance(snapshot: engine.snapshot(), at: now).liveWorkStart)
    }

    func testRunningCadenceIsWorkEvenWithoutHeartRate() {
        let engine = NetTimeEngine(kind: .running, profile: .default, startDate: start)
        _ = run(engine, from: 0, to: 30) {
            SensorSample(timestamp: self.start.addingTimeInterval(TimeInterval($0)), accelRMS: 0.05, cadence: 165)
        }
        XCTAssertEqual(engine.state, .work)
    }

    func testPauseExcludesTime() {
        let engine = NetTimeEngine(kind: .strength, profile: .default, startDate: start)
        _ = run(engine, from: 0, to: 10) { lifting($0) }
        engine.pause(at: start.addingTimeInterval(10))
        _ = run(engine, from: 10, to: 100) { lifting($0) }
        engine.resume(at: start.addingTimeInterval(100))
        _ = run(engine, from: 100, to: 110) { lifting($0) }
        XCTAssertEqual(engine.totals.total, 20, accuracy: 0.001)
        XCTAssertEqual(engine.pausedTime, 90, accuracy: 0.001)
    }

    func testSegmentsCoverWholeWorkout() {
        let engine = NetTimeEngine(kind: .strength, profile: .default, startDate: start)
        for round in 0..<4 {
            let base = round * 150
            _ = run(engine, from: base, to: base + 40) { lifting($0) }
            _ = run(engine, from: base + 40, to: base + 150) { sitting($0) }
        }
        let record = engine.finish(at: start.addingTimeInterval(600), source: .watch)
        let covered = record.segments.reduce(0) { $0 + $1.duration }
        XCTAssertEqual(covered, record.totals.total, accuracy: 0.01)
        XCTAssertEqual(record.sets, 4)
        XCTAssertFalse(record.points.isEmpty)
        XCTAssertNotNil(record.averageHeartRate)
        XCTAssertEqual(InsightBuilder.mergedBreaks(record.segments).count, 3)
    }

    func testRecordRoundTripsThroughJSON() throws {
        let engine = NetTimeEngine(kind: .hiit, profile: .default, startDate: start)
        _ = run(engine, from: 0, to: 200) { $0 % 60 < 30 ? lifting($0) : sitting($0, posture: .screenUp) }
        let record = engine.finish(at: start.addingTimeInterval(200), source: .phone)
        let message = SyncMessage.finished(record)
        guard case .finished(let decoded)? = SyncMessage.decode(message.encoded()) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(decoded, record)
    }

    func testFormat() {
        XCTAssertEqual(Format.clock(75), "1:15")
        XCTAssertEqual(Format.clock(3725), "1:02:05")
        XCTAssertEqual(Format.minutes(30), "30 sec")
        XCTAssertEqual(Format.minutes(3725), "1h 2m")
    }
}
