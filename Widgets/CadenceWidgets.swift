import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CadenceWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WeekWidget()
        NextCourseWidget()
        AccessoryStudyWidget()
        SessionLiveActivity()
    }
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
                .containerBackground(for: .widget) { WidgetCanvas() }
        }
        .configurationDisplayName("Cadenza aujourd’hui")
        .description("Vos durées de cours et de révision du jour, séparées des estimations.")
        .supportedFamilies([.systemSmall, .systemMedium])
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
                    Text(context.isStale ? "Ouvrir Cadenza pour actualiser" : context.state.isPaused ? "En pause" : "En cours")
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
                    .accessibilityLabel(context.state.isPaused ? "Cadenza en pause" : "Cadenza en cours")
            }
            .widgetURL(URL(string: "cadence://revision"))
            .keylineTint(.blue)
        }
    }
}
