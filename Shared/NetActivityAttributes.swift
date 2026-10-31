#if os(iOS)
import Foundation
import ActivityKit
import GymNetoKit

/// Live Activity (lock screen + Dynamic Island) for a running workout.
/// The changing part is a `NetGlance`.
struct NetActivityAttributes: ActivityAttributes {
    typealias ContentState = NetGlance

    var kind: WorkoutKind
    var startDate: Date
    var source: WorkoutSource
}
#endif
