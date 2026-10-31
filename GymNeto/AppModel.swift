import Foundation
import HealthKit
import WatchConnectivity
import GymNetoKit

/// iPhone app state: history, live watch workout mirror, settings sync.
@MainActor
final class AppModel: NSObject, ObservableObject {

    @Published var history: [WorkoutRecord] = []
    /// Live data streamed from the watch.
    @Published var watchLive: LiveSnapshot?
    /// Last finished workout to show as a sheet.
    @Published var justFinished: WorkoutRecord?
    @Published var profile: UserProfile = ProfileStore.load()

    let healthStore = HKHealthStore()
    private let fileURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("workouts.json")

    override init() {
        super.init()
        loadHistory()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: Health

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.activeEnergyBurned),
            HKCharacteristicType(.dateOfBirth)
        ]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
        var p = profile
        if let resting = await HealthBaselines.latestRestingHeartRate(store: healthStore) { p.restingHeartRate = resting }
        if let age = HealthBaselines.age(store: healthStore) { p.maxHeartRate = UserProfile.estimatedMaxHeartRate(age: age) }
        updateProfile(p)
    }

    /// Opens Gym Neto on the watch and starts the workout there.
    func startOnWatch(kind: WorkoutKind) async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = kind.activityType
        config.locationType = kind == .running ? .unknown : .indoor
        let store = healthStore
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.startWatchApp(with: config) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    var canUseWatch: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    // MARK: Demo

    func loadDemo() {
        profile = DemoData.profile
        history = DemoData.history
        watchLive = DemoData.liveSnapshot
    }

    // MARK: Settings

    func updateProfile(_ p: UserProfile) {
        profile = p
        ProfileStore.save(p)
        if WCSession.default.activationState == .activated {
            try? WCSession.default.updateApplicationContext(SyncMessage.profile(p).encoded())
        }
    }

    // MARK: History

    func add(_ record: WorkoutRecord) {
        guard !history.contains(where: { $0.id == record.id }) else { return }
        history.insert(record, at: 0)
        history.sort { $0.startDate > $1.startDate }
        saveHistory()
    }

    func delete(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([WorkoutRecord].self, from: data) else { return }
        history = list
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Weekly stats

    var thisWeek: Totals {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        var t = Totals()
        for r in history where r.startDate >= weekAgo {
            t.work += r.totals.work
            t.rest += r.totals.rest
            t.garbage += r.totals.garbage
            for (k, v) in r.totals.garbageByReason { t.garbageByReason[k, default: 0] += v }
        }
        return t
    }

    fileprivate func handle(_ message: SyncMessage) {
        switch message {
        case .live(let snap):
            watchLive = snap
            LiveActivityController.shared.update(with: snap, source: .watch)
        case .finished(let record):
            watchLive = nil
            add(record)
            justFinished = record
            LiveActivityController.shared.end(with: record)
        case .ended:
            watchLive = nil
            LiveActivityController.shared.end(with: nil)
        case .profile:
            break
        }
    }
}

extension AppModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let msg = SyncMessage.decode(message) else { return }
        Task { @MainActor in self.handle(msg) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let msg = SyncMessage.decode(userInfo) else { return }
        Task { @MainActor in self.handle(msg) }
    }
}
