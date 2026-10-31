import Foundation
import ActivityKit
import GymNetoKit

/// Starts, updates and ends the workout Live Activity.
///
/// Updates are throttled: the net-time number counts by itself on the lock screen
/// (system timer), so we only push when the state changes or every 30 s.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<NetActivityAttributes>?
    private var lastKey: String?
    private var lastUpdate = Date.distantPast

    func update(with snapshot: LiveSnapshot, source: WorkoutSource) {
        let glance = NetGlance(snapshot: snapshot)
        if activity == nil {
            activity = Activity<NetActivityAttributes>.activities.first { $0.attributes.startDate == snapshot.startDate }
        }
        guard let activity else {
            start(snapshot: snapshot, glance: glance, source: source)
            return
        }
        let key = "\(snapshot.state.rawValue)-\(snapshot.reason?.rawValue ?? "")-\(snapshot.isPaused)-\(snapshot.plannedRestRemaining != nil)"
        let now = Date()
        guard key != lastKey || now.timeIntervalSince(lastUpdate) >= 30 else { return }
        lastKey = key
        lastUpdate = now
        let content = ActivityContent(state: glance, staleDate: now.addingTimeInterval(120))
        Task { await activity.update(content) }
    }

    func end(with record: WorkoutRecord?) {
        let final = record.map { NetGlance().finishing($0) }
        let all = Activity<NetActivityAttributes>.activities
        activity = nil
        lastKey = nil
        Task {
            for a in all {
                let content = ActivityContent(state: final ?? a.content.state, staleDate: nil)
                await a.end(content, dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
            }
        }
    }

    /// Only works while the app is in the foreground (iOS rule). If the watch starts a workout while
    /// the phone app is closed, the Live Activity appears the next time you open Gym Neto.
    private func start(snapshot: LiveSnapshot, glance: NetGlance, source: WorkoutSource) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = NetActivityAttributes(kind: snapshot.kind, startDate: snapshot.startDate, source: source)
        activity = try? Activity.request(attributes: attributes,
                                         content: ActivityContent(state: glance, staleDate: Date().addingTimeInterval(120)))
        lastUpdate = Date()
    }
}
