import SwiftUI
import HealthKit
import WatchKit
import GymNetoKit

@main
struct GymNetoWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var manager = WorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(manager)
                .task {
                    PhoneConnector.shared.onProfile = { manager.updateProfile($0) }
                    PhoneConnector.shared.activate()
                    await manager.requestAuthorization()
                }
        }
    }
}

extension WorkoutManager {
    static let shared = WorkoutManager()
}

/// Lets the iPhone app start a workout on the watch (HKHealthStore.startWatchApp).
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            WorkoutManager.shared.start(configuration: workoutConfiguration)
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var manager: WorkoutManager

    var body: some View {
        switch manager.phase {
        case .idle:
            NavigationStack { StartView() }
        case .running:
            LiveTabView()
        case .summary:
            NavigationStack { WatchSummaryView() }
        }
    }
}

// MARK: - Start

struct StartView: View {
    @EnvironmentObject var manager: WorkoutManager

    var body: some View {
        List {
            ForEach(WorkoutKind.allCases) { kind in
                Button {
                    manager.start(kind: kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbol)
                        .font(.headline)
                        .foregroundStyle(Theme.work)
                        .padding(.vertical, 8)
                }
            }
            Section {
                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label("Rest settings", systemImage: "slider.horizontal.3")
                }
            }
        }
        .navigationTitle("Gym Neto")
    }
}

struct WatchSettingsView: View {
    @EnvironmentObject var manager: WorkoutManager

    var body: some View {
        let p = manager.profile
        List {
            Toggle("Auto rest", isOn: Binding(get: { p.autoRestEnabled }, set: { var n = p; n.autoRestEnabled = $0; manager.updateProfile(n) }))
            Stepper("Rest limit \(Format.clock(p.restAllowance))",
                    value: Binding(get: { p.restAllowance }, set: { var n = p; n.restAllowance = $0; manager.updateProfile(n) }),
                    in: 30...300, step: 15)
            Stepper("Rest timer \(Format.clock(p.plannedRestDuration))",
                    value: Binding(get: { p.plannedRestDuration }, set: { var n = p; n.plannedRestDuration = $0; manager.updateProfile(n) }),
                    in: 15...300, step: 15)
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Live

struct LiveTabView: View {
    @EnvironmentObject var manager: WorkoutManager
    @State private var tab = 1

    var body: some View {
        TabView(selection: $tab) {
            ControlsView().tag(0)
            LiveView().tag(1)
            BreakdownView().tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

struct LiveView: View {
    @EnvironmentObject var manager: WorkoutManager

    var body: some View {
        if let s = manager.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: s.state.symbol)
                    Text(s.state == .garbage ? (s.reason?.title ?? "Garbage") : s.state.title)
                    Spacer()
                    Text(Format.clock(s.stateDuration)).monospacedDigit()
                }
                .font(.footnote.bold())
                .foregroundStyle(s.state.color)

                Text(Format.clock(s.totals.work))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.work)
                Text("NET of \(Format.clock(s.elapsed))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                SplitBar(totals: s.totals, height: 8)

                HStack {
                    Label(s.heartRate.map { "\(Int($0))" } ?? "--", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Text("\(Format.percent(s.totals.netRatio))")
                        .foregroundStyle(Theme.work)
                    Spacer()
                    Text("Set \(s.sets)")
                }
                .font(.footnote.bold())
                .monospacedDigit()

                restButton(s)
            }
            .padding(.horizontal, 4)
            .opacity(s.isPaused ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private func restButton(_ s: LiveSnapshot) -> some View {
        if let remaining = s.plannedRestRemaining {
            Button {
                manager.cancelRest()
            } label: {
                Text("Rest \(Format.clock(remaining))").monospacedDigit()
            }
            .tint(Theme.rest)
        } else {
            Button {
                manager.startRest()
            } label: {
                Label("Rest \(Format.clock(manager.profile.plannedRestDuration))", systemImage: "timer")
            }
            .tint(Theme.rest)
        }
    }
}

struct BreakdownView: View {
    @EnvironmentObject var manager: WorkoutManager

    var body: some View {
        if let s = manager.snapshot {
            List {
                ForEach(ActivityState.allCases, id: \.self) { state in
                    HStack {
                        Label(state.title, systemImage: state.symbol).foregroundStyle(state.color)
                        Spacer()
                        Text(Format.clock(s.totals[state])).monospacedDigit()
                    }
                }
                ForEach(GarbageReason.allCases, id: \.self) { reason in
                    if let v = s.totals.garbageByReason[reason], v > 0 {
                        HStack {
                            Label(reason.title, systemImage: reason.symbol).font(.caption)
                            Spacer()
                            Text(Format.clock(v)).font(.caption).monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Label("Calories", systemImage: "flame")
                    Spacer()
                    Text("\(Int(s.calories))")
                }
            }
        }
    }
}

struct ControlsView: View {
    @EnvironmentObject var manager: WorkoutManager

    var body: some View {
        let paused = manager.snapshot?.isPaused ?? false
        HStack(spacing: 12) {
            VStack {
                Button { manager.end() } label: { Image(systemName: "xmark") }
                    .tint(.red).font(.title2)
                Text("End")
            }
            VStack {
                Button { manager.togglePause() } label: { Image(systemName: paused ? "play.fill" : "pause.fill") }
                    .tint(.yellow).font(.title2)
                Text(paused ? "Resume" : "Pause")
            }
        }
    }
}

// MARK: - Summary

struct WatchSummaryView: View {
    @EnvironmentObject var manager: WorkoutManager

    var body: some View {
        if let r = manager.record {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.grade).font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.work)
                        Text("Neto score \(r.netScore)").font(.footnote)
                    }
                    SplitBar(totals: r.totals)
                    row("Total", r.totals.total, .white)
                    row("Work", r.totals.work, Theme.work)
                    row("Rest", r.totals.rest, Theme.rest)
                    row("Garbage", r.totals.garbage, Theme.garbage)
                    ForEach(InsightBuilder.insights(for: r, profile: manager.profile).prefix(2)) { tip in
                        Text(tip.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                    Button("Done") { manager.reset() }.tint(Theme.work)
                }
            }
            .navigationTitle("Summary")
        }
    }

    private func row(_ title: String, _ value: TimeInterval, _ color: Color) -> some View {
        HStack {
            Text(title).foregroundStyle(color)
            Spacer()
            Text(Format.clock(value)).monospacedDigit()
        }
        .font(.headline)
    }
}
