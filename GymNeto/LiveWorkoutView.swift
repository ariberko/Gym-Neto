import SwiftUI
import GymNetoKit

/// Big live dashboard. Used for both the watch mirror and iPhone-only workouts.
struct LiveWorkoutView: View {
    let snapshot: LiveSnapshot
    let source: WorkoutSource

    var body: some View {
        VStack(spacing: 20) {
            statusPill

            ZStack {
                ring
                VStack(spacing: 4) {
                    Text("NET TIME").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(Format.clock(snapshot.totals.work))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.work)
                    Text("of \(Format.clock(snapshot.elapsed))")
                        .font(.title3).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .frame(width: 260, height: 260)

            HStack(spacing: 12) {
                tile(.work)
                tile(.rest)
                tile(.garbage)
            }

            HStack(spacing: 12) {
                metric("heart.fill", snapshot.heartRate.map { "\(Int($0))" } ?? "--", "BPM", .red)
                metric("bolt.fill", "\(Int(snapshot.effort * 100))", "EFFORT", .orange)
                metric("repeat", "\(snapshot.sets)", "SETS", .white)
                if source == .watch {
                    metric("flame.fill", "\(Int(snapshot.calories))", "KCAL", .pink)
                }
            }
        }
        .padding()
        .opacity(snapshot.isPaused ? 0.5 : 1)
        .animation(.easeInOut, value: snapshot.state)
    }

    private var statusPill: some View {
        HStack {
            Image(systemName: snapshot.state.symbol)
            if snapshot.state == .garbage {
                Text("\(snapshot.reason?.title ?? "Garbage time") · \(Format.clock(snapshot.stateDuration))")
            } else if let r = snapshot.plannedRestRemaining {
                Text("Rest timer \(Format.clock(r))")
            } else {
                Text("\(snapshot.state.title) · \(Format.clock(snapshot.stateDuration))")
            }
        }
        .font(.headline)
        .monospacedDigit()
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(snapshot.state.color.opacity(0.2), in: Capsule())
        .foregroundStyle(snapshot.state.color)
    }

    /// Three concentric arcs: work / rest / garbage share of total.
    private var ring: some View {
        let total = max(1, snapshot.totals.total)
        let w = snapshot.totals.work / total
        let r = snapshot.totals.rest / total
        return ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 18)
            Circle().trim(from: 0, to: w)
                .stroke(Theme.work, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
            Circle().trim(from: w, to: w + r)
                .stroke(Theme.rest, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
            Circle().trim(from: w + r, to: 1)
                .stroke(Theme.garbage, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                .opacity(snapshot.totals.garbage > 0 ? 1 : 0)
        }
        .rotationEffect(.degrees(-90))
    }

    private func tile(_ state: ActivityState) -> some View {
        VStack(spacing: 4) {
            Image(systemName: state.symbol)
            Text(Format.clock(snapshot.totals[state])).font(.title3.bold()).monospacedDigit()
            Text(state.title.uppercased()).font(.caption2.bold())
        }
        .foregroundStyle(state.color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(state.color.opacity(snapshot.state == state ? 0.25 : 0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ symbol: String, _ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Full-screen iPhone-only workout with controls.
struct PhoneLiveContainer: View {
    @ObservedObject var tracker: PhoneWorkoutTracker
    @EnvironmentObject var model: AppModel
    let onFinish: (WorkoutRecord?) -> Void

    var body: some View {
        VStack {
            if let s = tracker.snapshot {
                LiveWorkoutView(snapshot: s, source: .phone)
                Spacer()
                HStack(spacing: 12) {
                    if s.plannedRestRemaining != nil {
                        controlButton("Skip rest", "forward.fill", Theme.rest) { tracker.cancelRest() }
                    } else {
                        controlButton("Rest \(Format.clock(model.profile.plannedRestDuration))", "timer", Theme.rest) { tracker.startRest() }
                    }
                    controlButton(s.isPaused ? "Resume" : "Pause", s.isPaused ? "play.fill" : "pause.fill", .yellow) {
                        tracker.togglePause()
                    }
                    controlButton("End", "stop.fill", Theme.garbage) {
                        onFinish(tracker.finish())
                    }
                }
                .padding()
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func controlButton(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(color)
        }
    }
}
