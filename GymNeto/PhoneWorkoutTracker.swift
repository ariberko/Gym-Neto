import Foundation
import UIKit
import CoreMotion
import HealthKit
import GymNetoKit

/// iPhone-only mode (no watch). Tricks used:
/// - **Pocket mode**: proximity monitoring turns the screen off in your pocket while the app
///   keeps running, so motion is sampled live at 25 Hz.
/// - **App-switch detection**: if you leave the app while the phone is unlocked, that time is
///   flagged as Screen time (you were on Instagram, not on the bench).
/// - **Gap filling**: while the phone was locked we ask Core Motion what you were doing
///   (walking / running / still) and replay it through the engine.
/// - **Heart rate**: any heart-rate samples written to Apple Health during the session
///   (AirPods / chest strap apps / another watch app) are used live.
@MainActor
final class PhoneWorkoutTracker: ObservableObject {

    @Published var snapshot: LiveSnapshot?
    @Published var isRunning = false

    private var engine: NetTimeEngine?
    private let motion = MotionSampler(isWatch: false)
    private let activityManager = CMMotionActivityManager()
    private let healthStore: HKHealthStore
    private var hrQuery: HKAnchoredObjectQuery?
    private var heartRate: (bpm: Double, date: Date)?
    private var timer: Timer?
    private var backgroundedAt: Date?
    private var lockedAt: Date?
    private var observers: [NSObjectProtocol] = []
    private let haptics: UINotificationFeedbackGenerator

    var onEvent: ((EngineEvent) -> Void)?

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        self.haptics = UINotificationFeedbackGenerator()
    }

    func start(kind: WorkoutKind, profile: UserProfile) {
        let now = Date()
        engine = NetTimeEngine(kind: kind, profile: profile, startDate: now)
        motion.start()
        startHeartRateQuery(from: now)
        observeAppState()
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isProximityMonitoringEnabled = true
        isRunning = true
        snapshot = engine?.snapshot()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func startRest() {
        engine?.startPlannedRest()
        snapshot = engine?.snapshot()
    }

    func cancelRest() {
        engine?.cancelPlannedRest()
        snapshot = engine?.snapshot()
    }

    func togglePause() {
        guard let engine else { return }
        if engine.isPaused { engine.resume(at: Date()) } else { engine.pause(at: Date()) }
        snapshot = engine.snapshot()
    }

    func finish() -> WorkoutRecord? {
        timer?.invalidate()
        timer = nil
        motion.stop()
        if let q = hrQuery { healthStore.stop(q) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        UIApplication.shared.isIdleTimerDisabled = false
        UIDevice.current.isProximityMonitoringEnabled = false
        isRunning = false
        defer { engine = nil; snapshot = nil }
        guard let engine else { return nil }
        let record = engine.finish(at: Date(), source: .phone)
        saveToHealth(record)
        LiveActivityController.shared.end(with: record)
        return record
    }

    // MARK: Live

    private func tick() {
        guard let engine, backgroundedAt == nil else { return }
        let m = motion.read()
        let now = Date()
        let hr = heartRate.flatMap { now.timeIntervalSince($0.date) < 30 ? $0.bpm : nil }
        let sample = SensorSample(timestamp: now, heartRate: hr, accelRMS: m.accelRMS,
                                  rotationRMS: m.rotationRMS, cadence: m.cadence, posture: m.posture)
        let events = engine.ingest(sample)
        snapshot = engine.snapshot()
        if let snapshot { LiveActivityController.shared.update(with: snapshot, source: .phone) }
        for e in events {
            if e == .garbageNudge { haptics.notificationOccurred(.warning) }
            if e == .plannedRestFinished { haptics.notificationOccurred(.success) }
            onEvent?(e)
        }
    }

    // MARK: Background / lock handling

    private func observeAppState() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.backgroundedAt = Date() }
        })
        observers.append(nc.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lockedAt = Date() }
        })
        observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.fillGap() }
        })
    }

    private func fillGap() async {
        guard let engine, let from = backgroundedAt else { return }
        let now = Date()
        let lock = lockedAt.map { max(from, min($0, now)) }
        // Keep `backgroundedAt` set until the gap is replayed so live ticks wait.
        defer {
            backgroundedAt = nil
            lockedAt = nil
        }

        // 1. Unlocked & outside the app = using other apps.
        let phoneEnd = lock ?? now
        var t = from.addingTimeInterval(1)
        while t <= phoneEnd {
            engine.ingest(SensorSample(timestamp: t, accelRMS: 0, distracted: true))
            t.addTimeInterval(1)
        }

        // 2. Locked = ask Core Motion what happened.
        if let lock, now.timeIntervalSince(lock) > 1 {
            let activities = await motionActivities(from: lock, to: now)
            while t <= now {
                let a = activities.last { $0.startDate <= t }
                engine.ingest(Self.sample(at: t, activity: a))
                t.addTimeInterval(1)
            }
        }
        snapshot = engine.snapshot()
    }

    private func motionActivities(from: Date, to: Date) async -> [CMMotionActivity] {
        guard CMMotionActivityManager.isActivityAvailable() else { return [] }
        return await withCheckedContinuation { cont in
            activityManager.queryActivityStarting(from: from, to: to, to: .main) { list, _ in
                cont.resume(returning: list ?? [])
            }
        }
    }

    static func sample(at t: Date, activity: CMMotionActivity?) -> SensorSample {
        guard let a = activity else { return SensorSample(timestamp: t, accelRMS: 0.01, cadence: 0) }
        if a.running { return SensorSample(timestamp: t, accelRMS: 0.2, cadence: 160) }
        if a.cycling { return SensorSample(timestamp: t, accelRMS: 0.15, cadence: 0) }
        if a.walking { return SensorSample(timestamp: t, accelRMS: 0.05, cadence: 90) }
        return SensorSample(timestamp: t, accelRMS: 0.01, cadence: 0)
    }

    // MARK: Heart rate from Health

    private func startHeartRateQuery(from start: Date) {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-60), end: nil)
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, _ in
            guard let latest = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }) else { return }
            let bpm = latest.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            Task { @MainActor in self?.heartRate = (bpm, latest.endDate) }
        }
        let q = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        q.updateHandler = handler
        healthStore.execute(q)
        hrQuery = q
    }

    private func saveToHealth(_ record: WorkoutRecord) {
        guard record.totals.total >= 60 else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = record.kind.activityType
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        builder.beginCollection(withStart: record.startDate) { _, _ in
            builder.addMetadata([
                "GymNetoWorkSeconds": record.totals.work,
                "GymNetoRestSeconds": record.totals.rest,
                "GymNetoGarbageSeconds": record.totals.garbage,
                "GymNetoScore": record.netScore
            ]) { _, _ in
                builder.endCollection(withEnd: record.endDate) { _, _ in
                    builder.finishWorkout { _, _ in }
                }
            }
        }
    }
}
