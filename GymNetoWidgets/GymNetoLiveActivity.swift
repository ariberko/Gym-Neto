import SwiftUI
import WidgetKit
import ActivityKit
import GymNetoKit

@main
struct GymNetoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GymNetoLiveActivity()
    }
}

struct GymNetoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NetActivityAttributes.self) { context in
            LockScreenView(kind: context.attributes.kind, glance: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(Theme.work)
        } dynamicIsland: { context in
            let g = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(g.stateLabel, systemImage: g.state?.symbol ?? "flame.fill")
                        .font(.caption.bold())
                        .foregroundStyle(g.stateColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let hr = g.heartRate {
                        Label("\(hr)", systemImage: "heart.fill").font(.caption.bold()).foregroundStyle(.red)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    NetTimeText(glance: g)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.work)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        SplitBar(totals: g.totals, height: 6)
                        HStack {
                            Text("net of ").foregroundColor(.secondary) + Text(g.liveTotalStart ?? Date(), style: .timer)
                            Spacer()
                            Text("garbage \(Format.clock(g.garbage))").foregroundStyle(Theme.garbage)
                        }
                        .font(.caption)
                        .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: g.state?.symbol ?? "flame.fill").foregroundStyle(g.stateColor)
            } compactTrailing: {
                NetTimeText(glance: g)
                    .foregroundStyle(Theme.work)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: g.state?.symbol ?? "flame.fill").foregroundStyle(g.stateColor)
            }
            .keylineTint(g.stateColor)
        }
    }
}

struct LockScreenView: View {
    let kind: WorkoutKind
    let glance: NetGlance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(kind.title, systemImage: kind.symbol).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if glance.isLive {
                    Label(glance.stateLabel, systemImage: glance.state?.symbol ?? "flame.fill")
                        .font(.caption.bold())
                        .foregroundStyle(glance.stateColor)
                } else if let grade = glance.lastGrade {
                    Text("Done · \(grade)").font(.caption.bold()).foregroundStyle(Theme.work)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                NetTimeText(glance: glance)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.work)
                Text("net").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    TotalTimeText(glance: glance).font(.headline)
                    Text("total").font(.caption2).foregroundStyle(.secondary)
                }
            }
            SplitBar(totals: glance.totals, height: 8)
            HStack {
                Text("Rest \(Format.clock(glance.rest))").foregroundStyle(Theme.rest)
                Spacer()
                if let ends = glance.restEndsAt, glance.isLive {
                    Text("Back in ") + Text(timerInterval: Date()...max(Date(), ends), countsDown: true)
                }
                Spacer()
                Text("Garbage \(Format.clock(glance.garbage))").foregroundStyle(Theme.garbage)
            }
            .font(.caption.bold())
            .monospacedDigit()
        }
        .padding()
    }
}

extension NetGlance {
    /// Totals as of the last update (for the split bar).
    var totals: Totals {
        var t = Totals()
        t.work = work
        t.rest = rest
        t.garbage = garbage
        return t
    }
}
