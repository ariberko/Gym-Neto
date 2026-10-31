import SwiftUI
import WidgetKit
import GymNetoKit

// MARK: - Timeline

struct GlanceEntry: TimelineEntry {
    let date: Date
    let glance: NetGlance
}

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), glance: NetGlance(todayWork: 42 * 60, todayTotal: 61 * 60, lastGrade: "A", lastScore: 86))
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : GlanceEntry(date: Date(), glance: GlanceStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let glance = GlanceStore.load()
        let now = Date()
        var entries = [GlanceEntry(date: now, glance: glance)]
        // Reset "today" right after midnight.
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
            entries.append(GlanceEntry(date: midnight, glance: glance))
        }
        // While live, the watch app reloads us on every state change.
        completion(Timeline(entries: entries, policy: glance.isLive ? .after(now.addingTimeInterval(15 * 60)) : .never))
    }
}

// MARK: - Views

struct GlanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlanceEntry

    private var glance: NetGlance { entry.glance }
    private var color: Color { glance.state?.color ?? Theme.work }
    private var today: (work: TimeInterval, total: TimeInterval) { glance.todayValues(now: entry.date) }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    // Ring = share of real work.
    private var circular: some View {
        Gauge(value: glance.isLive ? glance.netRatio : ratio(today)) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            if glance.isLive {
                Text("\(Int(glance.work / 60))")
            } else {
                Text(glance.lastGrade ?? "\(Int(today.work / 60))")
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(color)
        .widgetAccentable()
    }

    private var corner: some View {
        Text(glance.isLive ? "\(Int(glance.work / 60))m" : "\(Int(today.work / 60))m")
            .foregroundStyle(color)
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: glance.isLive ? glance.netRatio : ratio(today)) { Text("Net") }
                    .tint(color)
            }
    }

    private var inline: some View {
        if glance.isLive {
            return Text("\(glance.state?.title ?? "Neto") · \(Format.clock(glance.work)) net")
        } else {
            return Text("Neto today \(Format.minutes(today.work))")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if glance.isLive {
                HStack(spacing: 4) {
                    Image(systemName: glance.state?.symbol ?? "flame.fill")
                    Text(glance.state == .garbage ? (glance.reason?.title ?? "Garbage") : (glance.state?.title ?? ""))
                    Spacer()
                    if let hr = glance.heartRate {
                        Image(systemName: "heart.fill")
                        Text("\(hr)")
                    }
                }
                .font(.caption2.bold())
                .foregroundStyle(color)
                NetTimeText(glance: glance)
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(Theme.work)
                    .widgetAccentable()
                Text("net · \(Format.percent(glance.netRatio)) focus")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("GYM NETO").font(.caption2.bold()).foregroundStyle(Theme.work)
                Text("\(Format.minutes(today.work)) net today")
                    .font(.headline)
                    .widgetAccentable()
                if let grade = glance.lastGrade, let score = glance.lastScore {
                    Text("Last: \(grade) · score \(score)").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Tap to start").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func ratio(_ t: (work: TimeInterval, total: TimeInterval)) -> Double {
        t.total > 0 ? t.work / t.total : 0
    }
}

// MARK: - Widget

@main
struct GymNetoWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GymNetoGlance", provider: GlanceProvider()) { entry in
            GlanceWidgetView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Net Time")
        .description("Your real workout time, live during a workout and today's total after.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}
