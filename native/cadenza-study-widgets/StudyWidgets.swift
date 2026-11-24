import ActivityKit
import SwiftUI
import WidgetKit

private let studyBlue = Color(red: 0.10, green: 0.36, blue: 0.84)

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
                if weekly, let days = data.weekDays, !days.isEmpty {
                    chart(Array(days.suffix(7)))
                } else {
                    Text("Cours et révisions").font(.caption).foregroundStyle(.secondary)
                }
                if let subject = data.topSubject, weekly, !subject.isEmpty {
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

    private func chart(_ days: [CadenzaStudySnapshot.Day]) -> some View {
        let peak = max(60, days.map(\.total).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Capsule().fill(studyBlue.opacity(day.total > 0 ? 0.88 : 0.2))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, 31 * day.total / peak))
            }
        }.frame(height: 31, alignment: .bottom)
            .accessibilityLabel("Temps suivi chaque jour de la semaine")
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
