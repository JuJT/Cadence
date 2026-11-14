import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CadenceWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        SessionLiveActivity()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: SharedSnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [TodayEntry(date: now, snapshot: SharedSnapshotStore.read())],
                            policy: .after(now.addingTimeInterval(900))))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CadenceAujourdHui", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Cadence aujourd’hui")
        .description("Cours et révisions. Sans partage autorisé, ouvre simplement Cadence.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cadence", systemImage: "book.closed.fill").font(.headline).foregroundStyle(.blue)
            if let value = entry.snapshot, Calendar.current.isDate(value.updatedAt, inSameDayAs: entry.date) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cours · \(CompactDuration.text(value.courseMeasured))")
                        Text("Estimés · \(CompactDuration.text(value.courseEstimated))").foregroundStyle(.secondary)
                        Text("Révisions · \(CompactDuration.text(value.revisions))")
                    }
                    if family == .systemMedium {
                        Spacer()
                        VStack(alignment: .leading, spacing: 3) {
                            if let subject = value.activeSubject {
                                Text(value.isPaused ? "En pause" : "En cours").font(.caption).foregroundStyle(.secondary)
                                Text(subject).font(.headline)
                            } else if let course = value.nextCourseTitle, let start = value.nextCourseStart {
                                Text("Prochain cours").font(.caption).foregroundStyle(.secondary)
                                Text(course).lineLimit(2)
                                Text(start, style: .time)
                            }
                        }
                    }
                }.font(.caption)
                Text("Actualisé à \(value.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Votre atelier d’étude").font(.subheadline)
                Text("Ouvrir Cadence").font(.caption).foregroundStyle(.secondary)
                Text("Données partagées indisponibles").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .widgetURL(URL(string: "cadence://accueil"))
        .accessibilityElement(children: .combine)
    }
}

struct LiveElapsedText: View {
    let state: SessionActivityAttributes.ContentState
    var body: some View {
        Group {
            if let start = state.runningSince, !state.isPaused {
                Text(timerInterval: start...start.addingTimeInterval(86400 * 366), countsDown: false)
            } else {
                Text(CompactDuration.clock(state.elapsedSeconds))
            }
        }.monospacedDigit().accessibilityLabel(state.isPaused ? "Temps actif en pause" : "Temps actif écoulé")
    }
}

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.symbol).font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(context.state.kindLabel) · \(context.state.subjectName)").font(.headline)
                    Text(context.isStale ? "Ouvrir Cadence pour actualiser" : context.state.isPaused ? "En pause" : "En cours")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                LiveElapsedText(state: context.state).font(.title3.weight(.semibold))
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "cadence://revision"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.kindLabel, systemImage: context.state.symbol).font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveElapsedText(state: context.state).frame(maxWidth: 95).font(.headline)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.subjectName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.isPaused ? "En pause" : "En cours").foregroundStyle(.secondary)
                        Spacer()
                        Link("Ouvrir les commandes", destination: URL(string: "cadence://revision")!)
                    }.font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(.blue).accessibilityLabel(context.state.kindLabel)
            } compactTrailing: {
                LiveElapsedText(state: context.state).frame(width: 65).font(.caption2)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : context.state.symbol)
                    .accessibilityLabel(context.state.isPaused ? "Cadence en pause" : "Cadence en cours")
            }
            .widgetURL(URL(string: "cadence://revision"))
            .keylineTint(.blue)
        }
    }
}
