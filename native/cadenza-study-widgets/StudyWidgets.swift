import ActivityKit
import SwiftUI
import WidgetKit

private let studyBlue = Color(red: 0.10, green: 0.36, blue: 0.84)
private let studyMeasured = Color(red: 0.03, green: 0.46, blue: 0.52)
private let studyScheduled = Color(red: 0.40, green: 0.47, blue: 0.58)

private struct CadenzaWidgetEntry: TimelineEntry {
    let date: Date
    let data: CadenzaStudySnapshot?
}

private struct CadenzaStudyProvider: TimelineProvider {
    func placeholder(in context: Context) -> CadenzaWidgetEntry { .init(date: .now, data: nil) }
    func getSnapshot(in context: Context, completion: @escaping (CadenzaWidgetEntry) -> Void) {
        completion(.init(date: .now, data: CadenzaWidgetStore.snapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CadenzaWidgetEntry>) -> Void) {
        let entry = CadenzaWidgetEntry(date: .now, data: CadenzaWidgetStore.snapshot())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(1800))))
    }
}

private struct CadenzaStudyOverview: View {
    @Environment(\.widgetFamily) private var family
    let entry: CadenzaWidgetEntry
    let weekly: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(weekly ? "Ma semaine" : "Aujourd’hui", systemImage: weekly ? "chart.bar.xaxis" : "timer")
                .font(.subheadline.weight(.semibold)).foregroundStyle(studyBlue)
            Spacer(minLength: 0)
            if let data = entry.data {
                Text(CadenzaDuration.total(weekly ? data.weekSeconds : data.todaySeconds))
                    .font(.title2.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.65)
                if let breakdown = breakdown(data) {
                    if weekly, family == .systemMedium, let days = data.weekDays, !days.isEmpty {
                        HStack(alignment: .center, spacing: 14) {
                            breakdownRows(breakdown)
                            chart(Array(days.suffix(7)))
                        }
                    } else {
                        breakdownRows(breakdown)
                    }
                } else if weekly, let days = data.weekDays, !days.isEmpty {
                    chart(Array(days.suffix(7)))
                } else {
                    Text("Cours et révisions").font(.caption).foregroundStyle(.secondary)
                }
                if let subject = data.topSubject, weekly, family == .systemMedium, !subject.isEmpty {
                    Text(subject).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                }
            } else {
                Text("Ouvrez Cadenza pour retrouver le suivi.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(CadenzaWidgetStore.studyURL)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private struct Breakdown {
        let revisions: Double
        let measured: Double
        let scheduled: Double
    }

    private func breakdown(_ data: CadenzaStudySnapshot) -> Breakdown? {
        guard let revisions = weekly ? data.weekRevisionSeconds : data.todayRevisionSeconds,
              let measured = weekly ? data.weekMeasuredCourseSeconds : data.todayMeasuredCourseSeconds,
              let scheduled = weekly ? data.weekScheduledCourseSeconds : data.todayScheduledCourseSeconds else { return nil }
        return Breakdown(revisions: revisions, measured: measured, scheduled: scheduled)
    }

    private func breakdownRows(_ breakdown: Breakdown) -> some View {
        VStack(spacing: 3) {
            metric("Révisions", breakdown.revisions, color: studyBlue)
            metric("Cours mesurés", breakdown.measured, color: studyMeasured)
            metric("Emploi du temps", breakdown.scheduled, color: studyScheduled)
        }
    }

    private func metric(_ title: String, _ seconds: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5).accessibilityHidden(true)
            Text(title).lineLimit(1)
            Spacer(minLength: 2)
            Text(CadenzaDuration.total(seconds)).monospacedDigit().lineLimit(1).layoutPriority(1)
        }
        .font(.caption2)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    private func chart(_ days: [CadenzaStudySnapshot.Day]) -> some View {
        let peak = max(60, days.map(\.total).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if day.total > 0, let measured = day.measuredCourseSeconds, let scheduled = day.scheduledCourseSeconds {
                    VStack(spacing: 0) {
                        bar(seconds: day.revisionSeconds, peak: peak, color: studyBlue)
                        bar(seconds: measured, peak: peak, color: studyMeasured)
                        bar(seconds: scheduled, peak: peak, color: studyScheduled)
                    }.clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Capsule().fill(studyBlue.opacity(day.total > 0 ? 0.88 : 0.2))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, 31 * day.total / peak))
                }
            }
        }.frame(height: 31, alignment: .bottom)
            .accessibilityLabel("Temps suivi chaque jour de la semaine")
    }

    @ViewBuilder private func bar(seconds: Double, peak: Double, color: Color) -> some View {
        if seconds > 0 {
            Rectangle().fill(color).frame(maxWidth: .infinity).frame(height: 31 * seconds / peak)
        }
    }
}

struct CadenzaStudyTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CadenzaWidgetStore.todayKind, provider: CadenzaStudyProvider()) { entry in
            CadenzaStudyOverview(entry: entry, weekly: false)
        }
        .configurationDisplayName("Temps d’étude")
        .description("Les cours et révisions de la journée.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CadenzaStudyWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CadenzaWidgetStore.weekKind, provider: CadenzaStudyProvider()) { entry in
            CadenzaStudyOverview(entry: entry, weekly: true)
        }
        .configurationDisplayName("Ma semaine d’étude")
        .description("Le temps travaillé au fil de la semaine.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CadenzaRevisionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CadenzaRevisionAttributes.self) { context in
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: context.state.paused ? "pause.circle.fill" : "timer")
                    .font(.title2).foregroundStyle(studyBlue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                    Text(context.state.paused ? "En pause" : context.state.kind == "course" ? "Cours en cours" : "Révision en cours")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                timer(context.state).font(.title3.bold().monospacedDigit()).frame(minWidth: 60)
            }.padding(15).widgetURL(CadenzaWidgetStore.studyURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer").foregroundStyle(studyBlue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state).font(.headline.monospacedDigit()).frame(minWidth: 58)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.title).font(.subheadline).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.paused ? "pause.fill" : "timer").foregroundStyle(.tint)
            } compactTrailing: {
                timer(context.state).font(.caption.monospacedDigit()).frame(width: 46)
            } minimal: {
                Image(systemName: "timer")
            }.widgetURL(CadenzaWidgetStore.studyURL)
        }
    }

    private func timer(_ state: CadenzaRevisionAttributes.ContentState) -> Text {
        state.paused ? Text(CadenzaDuration.clock(state.elapsedSeconds)) : Text(state.start, style: .timer)
    }
}

private enum CadenzaDuration {
    static func total(_ duration: Double) -> String {
        let minutes = Int(max(0, min(duration, 100_000_000))) / 60
        return minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    static func clock(_ duration: Double) -> String {
        let seconds = Int(max(0, min(duration, 100_000_000)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
