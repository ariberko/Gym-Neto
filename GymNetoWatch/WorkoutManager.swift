import Foundation
import HealthKit
import WatchKit
import GymNetoKit

/// Runs a real HealthKit workout session on the watch (keeps the app alive with the
/// screen down, streams live heart rate + energy), fuses it with motion data every
/// second and feeds the NetTimeEngine.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    enum Phase { case idle, running, summary }

    @Published var phase: Phase = .idle
    @Published var snapshot: LiveSnapshot?
    @Published var record: WorkoutRecord?
    @Published var profile: UserProfile = ProfileStore.load()

    let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var engine: NetTimeEngine?
    private let motion = MotionSampler(isWatch: true)
    private var timer: Timer?
    private var tick = 0

    // Latest HealthKit values.
    private var heartRate: Double?
    private var heartRateDate: Date?
    private var energyTotal: Double = 0
    private var energyHistory: [(date: Date, kcal: Double)] = []

    // Watch face widget bookkeeping.
    private var glanceKey: String?
    private var lastWidgetReload = Date.distantPast

    // MARK: Authorization

    func requestAuthorization() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKCharacteristicType(.dateOfBirth),
            HKObjectType.activitySummaryType()
        ]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
        await refreshBaselines()
    }

    /// Pull resting HR and age from Apple Health so effort is personal.
    func refreshBaselines() async {
        var p = profile
        if let resting = await HealthBaselines.latestRestingHeartRate(store: healthStore) {
            p.restingHeartRate = resting
        }
        if let age = HealthBaselines.age(store: healthStore) {
            p.maxHeartRate = UserProfile.estimatedMaxHeartRate(age: age)
        }
        updateProfile(p)
    }

    func updateProfile(_ p: UserProfile) {
        profile = p
        ProfileStore.save(p)
        engine?.update(profile: p)
    }

    // MARK: Lifecycle

    func start(kind: WorkoutKind) {
        let config = HKWorkoutConfiguration()
        config.activityType = kind.activityType
        config.locationType = kind == .running ? .unknown : .indoor
        start(configuration: config)
    }

    func start(configuration: HKWorkoutConfiguration) {
        guard phase != .running else { return }
        let kind = WorkoutKind(activityType: configuration.activityType)
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let start = Date()
            engine = NetTimeEngine(kind: kind, profile: profile, startDate: start)
            heartRate = nil
            energyTotal = 0
            energyHistory = []
            record = nil
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            motion.start()
            startTimer()
            phase = .running
            snapshot = engine?.snapshot()
            glanceKey = nil
            updateGlance(force: true)
            WKInterfaceDevice.current().play(.start)
        } catch {
            print("Could not start workout: \(error)")
        }
    }

    func togglePause() {
        guard let session else { return }
        if session.state == .running { session.pause() } else { session.resume() }
    }

    func startRest() {
        engine?.startPlannedRest()
        snapshot = engine?.snapshot()
        WKInterfaceDevice.current().play(.click)
    }

    func cancelRest() {
        engine?.cancelPlannedRest()
        snapshot = engine?.snapshot()
    }

    func end() {
        timer?.invalidate()
        timer = nil
        motion.stop()
        let endDate = Date()
        guard let engine else { return }
        engine.calories = energyTotal
        let record = engine.finish(at: endDate, source: .watch)
        self.record = record
        phase = .summary
        PhoneConnector.shared.send(.finished(record), reliable: true)
        GlanceStore.save(GlanceStore.load().finishing(record), reloadWidgets: true)

        session?.end()
        guard let builder else { return }
        builder.addMetadata(Self.metadata(for: record)) { _, _ in
            builder.endCollection(withEnd: endDate) { _, _ in
                builder.finishWorkout { _, _ in }
            }
        }
        WKInterfaceDevice.current().play(.stop)
    }

    func reset() {
        session = nil
        builder = nil
        engine = nil
        snapshot = nil
        record = nil
        phase = .idle
    }

    static func metadata(for record: WorkoutRecord) -> [String: Any] {
        [
            "GymNetoWorkSeconds": record.totals.work,
            "GymNetoRestSeconds": record.totals.rest,
            "GymNetoGarbageSeconds": record.totals.garbage,
            "GymNetoScore": record.netScore,
            HKMetadataKeyIndoorWorkout: record.kind != .running
        ]
    }

    // MARK: Tick

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func onTick() {
        guard let engine else { return }
        let now = Date()
        let m = motion.read()
        let freshHR = (heartRateDate.map { now.timeIntervalSince($0) < 15 } ?? false) ? heartRate : nil
        let sample = SensorSample(timestamp: now,
                                  heartRate: freshHR,
                                  accelRMS: m.accelRMS,
                                  rotationRMS: m.rotationRMS,
                                  cadence: m.cadence,
                                  energyRate: energyRate(now: now),
                                  posture: m.posture)
        engine.calories = energyTotal
        let events = engine.ingest(sample)
        snapshot = engine.snapshot()
        handle(events)
        updateGlance(force: false)

        tick += 1
        if tick % 2 == 0, let snap = snapshot {
            PhoneConnector.shared.send(.live(snap), reliable: false)
        }
    }

    private func handle(_ events: [EngineEvent]) {
        let device = WKInterfaceDevice.current()
        for event in events {
            switch event {
            case .garbageNudge: device.play(.retry)          // "get back to it"
            case .plannedRestFinished: device.play(.notification)
            case .startedWork, .startedRest, .startedGarbage: break
            }
        }
    }

    /// Keeps the watch face complication in sync. Widget reloads have a budget,
    /// so we only reload when the state changes (at most every 10 s) or every 5 minutes.
    private func updateGlance(force: Bool) {
        guard let snap = snapshot else { return }
        let key = "\(snap.state.rawValue)-\(snap.reason?.rawValue ?? "")-\(snap.isPaused)-\(snap.plannedRestRemaining != nil)"
        let now = Date()
        let changed = key != glanceKey
        let sinceReload = now.timeIntervalSince(lastWidgetReload)
        guard force || (changed && sinceReload >= 10) || sinceReload >= 300 else { return }
        glanceKey = key
        lastWidgetReload = now
        GlanceStore.save(GlanceStore.load().merging(live: snap, at: now), reloadWidgets: true)
    }

    /// kcal per minute over the last ~30 s.
    private func energyRate(now: Date) -> Double? {
        energyHistory.removeAll { now.timeIntervalSince($0.date) > 30 }
        guard let first = energyHistory.first, let last = energyHistory.last,
              last.date.timeIntervalSince(first.date) >= 10 else { return nil }
        return (last.kcal - first.kcal) / last.date.timeIntervalSince(first.date) * 60
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .paused: self.engine?.pause(at: date)
            case .running: self.engine?.resume(at: date)
            default: break
            }
            self.snapshot = self.engine?.snapshot()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var hr: Double?
        var kcal: Double?
        for type in collectedTypes {
            guard let q = type as? HKQuantityType, let stats = workoutBuilder.statistics(for: q) else { continue }
            if q == HKQuantityType(.heartRate) {
                hr = stats.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
            } else if q == HKQuantityType(.activeEnergyBurned) {
                kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie())
            }
        }
        let hrValue = hr, kcalValue = kcal
        Task { @MainActor in
            let now = Date()
            if let hr = hrValue {
                self.heartRate = hr
                self.heartRateDate = now
            }
            if let kcal = kcalValue {
                self.energyTotal = kcal
                self.energyHistory.append((now, kcal))
            }
        }
    }
}
