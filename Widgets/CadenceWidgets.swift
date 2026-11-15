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
            Label("Cadence", systemImage: "book.closed.fill")
                .font(.headline).foregroundStyle(.blue).lineLimit(1).minimumScaleFactor(0.85)
            if let value = entry.snapshot, Calendar.current.isDate(value.updatedAt, inSameDayAs: entry.date) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cours · \(CompactDuration.text(value.courseMeasured))")
                        Text("Estimés · \(CompactDuration.text(value.courseEstimated))").foregroundStyle(.secondary)
                        Text("Révisions · \(CompactDuration.text(value.revisions))")
                    }.lineLimit(1).minimumScaleFactor(0.85)
                    if family == .systemMedium {
                        Spacer(minLength: 12)
                        VStack(alignment: .leading, spacing: 3) {
                            if let subject = value.activeSubject {
                                Text(value.isPaused ? "En pause" : "En cours").font(.caption).foregroundStyle(.secondary)
                                Text(subject).font(.headline).lineLimit(2).minimumScaleFactor(0.85)
                            } else if let course = value.nextCourseTitle, let start = value.nextCourseStart {
                                Text("Prochain cours").font(.caption).foregroundStyle(.secondary)
                                Text(course).lineLimit(2).minimumScaleFactor(0.85)
                                Text(start, style: .time)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.font(.caption)
                Text("Actualisé à \(value.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
            } else {
                Spacer(minLength: 0)
                Text(family == .systemSmall ? "Vos cours et révisions" : "Retrouvez vos cours et vos révisions dans l’app.")
                    .font(family == .systemSmall ? .subheadline : .body)
                    .lineLimit(2).minimumScaleFactor(0.9)
                Label("Ouvrir Cadence", systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        .multilineTextAlignment(.trailing)
        .accessibilityLabel(state.isPaused ? "Temps actif en pause" : "Temps actif écoulé")
    }
}

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.symbol).font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.kindLabel).font(.caption).foregroundStyle(.secondary)
                    Text(context.state.subjectName).font(.headline).lineLimit(2).minimumScaleFactor(0.85)
                    Text(context.isStale ? "Ouvrir Cadence pour actualiser" : context.state.isPaused ? "En pause" : "En cours")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                LiveElapsedText(state: context.state)
                    .font(.title3.weight(.semibold)).frame(width: 92, alignment: .trailing)
            }
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "cadence://revision"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.kindLabel, systemImage: context.state.symbol)
                        .font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveElapsedText(state: context.state)
                        .font(.headline).frame(width: 88, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // The full-width region keeps long subject names clear of the camera
                    // and gives the footer matching insets from the island's rounded edge.
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.subjectName)
                            .font(.headline).lineLimit(2).minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 12) {
                            Text(context.isStale ? "À actualiser" : context.state.isPaused ? "En pause" : "En cours")
                                .foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 0)
                            Link(destination: URL(string: "cadence://revision")!) {
                                Label("Ouvrir", systemImage: "arrow.up.right")
                                    .labelStyle(.titleAndIcon)
                            }.accessibilityLabel("Ouvrir les commandes de la séance")
                        }.font(.caption.weight(.medium))
                    }.padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(.blue).accessibilityLabel(context.state.kindLabel)
            } compactTrailing: {
                LiveElapsedText(state: context.state).font(.caption2).frame(width: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : context.state.symbol)
                    .accessibilityLabel(context.state.isPaused ? "Cadence en pause" : "Cadence en cours")
            }
            .widgetURL(URL(string: "cadence://revision"))
            .keylineTint(.blue)
        }
    }
}
