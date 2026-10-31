import SwiftUI
import HealthKit
import GymNetoKit

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var phoneTracker = PhoneWorkoutTracker(healthStore: HKHealthStore())
    @State private var showStart = false
    @State private var showSettings = false
    @State private var phoneSummary: WorkoutRecord?
    @State private var startError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let live = model.watchLive {
                        NavigationLink {
                            LiveWorkoutView(snapshot: live, source: .watch)
                        } label: {
                            LiveCard(snapshot: live)
                        }
                        .buttonStyle(.plain)
                    }

                    weekCard

                    Button {
                        showStart = true
                    } label: {
                        Label("Start workout", systemImage: "play.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.work, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.black)
                    }

                    if let startError {
                        Text(startError).font(.footnote).foregroundStyle(Theme.garbage)
                    }

                    historySection
                }
                .padding()
            }
            .navigationTitle("Gym Neto")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .sheet(isPresented: $showStart) { startSheet }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(model) }
            .sheet(item: $model.justFinished) { r in
                NavigationStack { SummaryView(record: r) }.environmentObject(model)
            }
            .sheet(item: $phoneSummary) { r in
                NavigationStack { SummaryView(record: r) }.environmentObject(model)
            }
            .fullScreenCover(isPresented: $phoneTracker.isRunning) {
                PhoneLiveContainer(tracker: phoneTracker) { record in
                    if let record {
                        model.add(record)
                        // Wait for the full-screen cover to dismiss before showing the sheet.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { phoneSummary = record }
                    }
                }
                .environmentObject(model)
            }
        }
    }

    // MARK: Week

    private var weekCard: some View {
        let t = model.thisWeek
        return VStack(alignment: .leading, spacing: 10) {
            Text("LAST 7 DAYS").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(Format.minutes(t.work)).font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.work)
                Text("of real work").foregroundStyle(.secondary)
            }
            SplitBar(totals: t)
            HStack {
                legend(.work, t.work)
                Spacer()
                legend(.rest, t.rest)
                Spacer()
                legend(.garbage, t.garbage)
            }
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func legend(_ state: ActivityState, _ value: TimeInterval) -> some View {
        Label(Format.minutes(value), systemImage: state.symbol)
            .font(.footnote.bold())
            .foregroundStyle(state.color)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HISTORY").font(.caption.bold()).foregroundStyle(.secondary)
            if model.history.isEmpty {
                Text("No workouts yet. Start one on your Apple Watch or right here.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical)
            }
            ForEach(model.history) { r in
                NavigationLink {
                    SummaryView(record: r)
                } label: {
                    HistoryRow(record: r)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Start

    private var startSheet: some View {
        NavigationStack {
            List {
                Section("On Apple Watch (best)") {
                    ForEach(WorkoutKind.allCases) { kind in
                        Button {
                            showStart = false
                            Task {
                                do { try await model.startOnWatch(kind: kind); startError = nil }
                                catch { startError = "Could not reach your watch. Open Gym Neto on it and try again." }
                            }
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                }
                Section {
                    ForEach(WorkoutKind.allCases) { kind in
                        Button {
                            showStart = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                phoneTracker.start(kind: kind, profile: model.profile)
                            }
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                } header: {
                    Text("iPhone only")
                } footer: {
                    Text("Keep the app open and put the phone in your pocket - the screen turns off by itself. Leaving the app while unlocked counts as screen time.")
                }
            }
            .navigationTitle("Start")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Rows & cards

struct HistoryRow: View {
    let record: WorkoutRecord

    var body: some View {
        HStack(spacing: 12) {
            Text(record.grade)
                .font(.title2.weight(.heavy))
                .frame(width: 48, height: 48)
                .background(Theme.card, in: Circle())
                .foregroundStyle(Theme.work)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(record.kind.title, systemImage: record.kind.symbol).font(.headline)
                    Spacer()
                    Text(record.startDate, format: .dateTime.day().month().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("\(Format.clock(record.totals.work)) net of \(Format.clock(record.totals.total))")
                    .font(.subheadline).foregroundStyle(.secondary)
                SplitBar(totals: record.totals, height: 6)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct LiveCard: View {
    let snapshot: LiveSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("LIVE ON WATCH", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.caption.bold())
                Spacer()
                Text(snapshot.state.title.uppercased()).font(.caption.bold()).foregroundStyle(snapshot.state.color)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Format.clock(snapshot.totals.work))
                    .font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.work)
                Text("net of \(Format.clock(snapshot.elapsed))").foregroundStyle(.secondary)
            }
            SplitBar(totals: snapshot.totals)
        }
        .padding()
        .background(snapshot.state.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(snapshot.state.color, lineWidth: 1))
    }
}
