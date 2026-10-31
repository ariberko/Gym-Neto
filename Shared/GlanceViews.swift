import SwiftUI
import GymNetoKit

/// Net time that keeps counting by itself (system timer) while you work,
/// and freezes when you rest - no app updates needed every second.
struct NetTimeText: View {
    let glance: NetGlance

    var body: some View {
        if let start = glance.liveWorkStart {
            Text(start, style: .timer).monospacedDigit()
        } else {
            Text(Format.clock(glance.work)).monospacedDigit()
        }
    }
}

struct TotalTimeText: View {
    let glance: NetGlance

    var body: some View {
        if let start = glance.liveTotalStart {
            Text(start, style: .timer).monospacedDigit()
        } else {
            Text(Format.clock(glance.total)).monospacedDigit()
        }
    }
}

extension NetGlance {
    var stateLabel: String {
        if isPaused { return "Paused" }
        guard let state else { return "Gym Neto" }
        if state == .garbage { return reason?.title ?? "Garbage" }
        if restEndsAt != nil { return "Rest timer" }
        return state.title
    }

    var stateColor: Color { isPaused ? .yellow : (state?.color ?? Theme.work) }
}
