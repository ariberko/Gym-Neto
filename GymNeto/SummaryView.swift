import SwiftUI
import Charts
import GymNetoKit

struct SummaryView: View {
    let record: WorkoutRecord
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                donut
                timeline
                if record.points.contains(where: { $0.heartRate != nil }) { heartChart }
                garbageBreakdown
                insights
                stats
            }
            .padding()
        }
        .navigationTitle(record.kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(record.grade)
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(Theme.work)
            VStack(alignment: .leading, spacing: 4) {
                Text("Neto score \(record.netScore)").font(.title3.bold())
                Text("\(Format.clock(record.totals.work)) of real work in \(Format.clock(record.totals.total))")
                    .foregroundStyle(.secondary)
                Text(record.startDate, format: .dateTime.weekday(.wide).day().month().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Donut

    private var donut: some View {
        HStack(spacing: 20) {
            Chart(ActivityState.allCases, id: \.self) { state in
                SectorMark(angle: .value("Time", record.totals[state]), innerRadius: .ratio(0.62), angularInset: 2)
                    .foregroundStyle(state.color)
                    .cornerRadius(4)
            }
            .chartLegend(.hidden)
            .frame(width: 150, height: 150)
            .overlay {
                VStack(spacing: 0) {
                    Text(Format.percent(record.totals.netRatio)).font(.title.bold())
                    Text("net").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ActivityState.allCases, id: \.self) { state in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.title.uppercased()).font(.caption.bold()).foregroundStyle(state.color)
                        Text(Format.clock(record.totals[state])).font(.title3.bold()).monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIMELINE").font(.caption.bold()).foregroundStyle(.secondary)
            Chart(record.segments) { s in
                BarMark(xStart: .value("Start", s.start / 60), xEnd: .value("End", s.end / 60), y: .value("Lane", "x"))
                    .foregroundStyle(s.state.color)
            }
            .chartYAxis(.hidden)
            .chartXAxisLabel("minutes")
            .frame(height: 60)
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var heartChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HEART RATE").font(.caption.bold()).foregroundStyle(.secondary)
            Chart {
                // Colored bands behind the line show what you were doing.
                ForEach(record.segments) { s in
                    RectangleMark(xStart: .value("Start", s.start / 60), xEnd: .value("End", s.end / 60))
                        .foregroundStyle(s.state.color.opacity(0.18))
                }
                ForEach(record.points) { p in
                    if let hr = p.heartRate {
                        LineMark(x: .value("Min", p.offset / 60), y: .value("BPM", hr))
                            .foregroundStyle(.white)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxisLabel("minutes")
            .chartYAxisLabel("bpm")
            .frame(height: 180)
            HStack(spacing: 14) {
                ForEach(ActivityState.allCases, id: \.self) { state in
                    Label(state.title, systemImage: "square.fill")
                        .font(.caption2)
                        .foregroundStyle(state.color)
                }
            }
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Garbage

    @ViewBuilder
    private var garbageBreakdown: some View {
        let reasons = GarbageReason.allCases.filter { (record.totals.garbageByReason[$0] ?? 0) > 0 }
        if !reasons.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHERE THE GARBAGE TIME WENT").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(reasons, id: \.self) { reason in
                    HStack {
                        Label(reason.title, systemImage: reason.symbol)
                        Spacer()
                        Text(Format.clock(record.totals.garbageByReason[reason] ?? 0)).monospacedDigit().bold()
                    }
                    .foregroundStyle(Theme.garbage)
                }
                Text("Longest stretch: \(Format.clock(record.longestGarbage))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .background(Theme.garbage.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var insights: some View {
        let tips = InsightBuilder.insights(for: record, profile: model.profile, history: model.history)
        return VStack(alignment: .leading, spacing: 12) {
            if !tips.isEmpty { Text("COACH").font(.caption.bold()).foregroundStyle(.secondary) }
            ForEach(tips) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tip.symbol)
                        .foregroundStyle(tip.tone == .good ? Theme.work : tip.tone == .warning ? Theme.garbage : Theme.rest)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title).bold()
                        Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var stats: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            GridRow { Text("Sets / bouts").foregroundStyle(.secondary); Text("\(record.sets)").bold() }
            if let avg = record.averageHeartRate {
                GridRow { Text("Avg heart rate").foregroundStyle(.secondary); Text("\(Int(avg)) bpm").bold() }
            }
            if let max = record.maxHeartRate {
                GridRow { Text("Max heart rate").foregroundStyle(.secondary); Text("\(Int(max)) bpm").bold() }
            }
            if record.calories > 0 {
                GridRow { Text("Active calories").foregroundStyle(.secondary); Text("\(Int(record.calories)) kcal").bold() }
            }
            if record.pausedTime > 1 {
                GridRow { Text("Paused").foregroundStyle(.secondary); Text(Format.clock(record.pausedTime)).bold() }
            }
            GridRow {
                Text("Tracked with").foregroundStyle(.secondary)
                Text(record.source == .watch ? "Apple Watch" : "iPhone").bold()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
