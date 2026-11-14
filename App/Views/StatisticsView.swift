import SwiftUI
import Charts
import CadenceCore

struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var kind: SessionKind?
    @State private var period = "Semaine"
    @State private var date = Date()
    private var component: Calendar.Component { period == "Jour" ? .day : period == "Mois" ? .month : .weekOfYear }
    private var interval: DateInterval { Calendar.current.dateInterval(of: component, for: date)! }
    private var totals: StudyTotals { Statistics.totals(state: store.state, in: interval, now: .now) }
    private var displayedTotal: Double {
        kind == .course ? totals.courseMeasured + totals.courseEstimated : kind == .revision ? totals.revisions : totals.total
    }
    private var dailyData: [DayTotals] {
        var result: [DayTotals] = []
        var cursor = interval.start
        while cursor < interval.end {
            let day = Atelier.day(cursor)
            result.append(DayTotals(date: cursor, totals: Statistics.totals(state: store.state, in: day, now: .now)))
            cursor = day.end
        }
        return result
    }
    private var subjectData: [(subject: Subject, seconds: Double)] {
        let values = Statistics.bySubject(state: store.state, in: interval, now: .now)
        return store.state.subjects.compactMap { subject in
            guard let value = values[subject.id] else { return nil }
            let seconds = kind == .course ? value.courseMeasured + value.courseEstimated : kind == .revision ? value.revisions : value.total
            return seconds > 0 ? (subject, seconds) : nil
        }.sorted { $0.seconds > $1.seconds }
    }
    var body: some View {
        AtelierPage {
            Picker("Type", selection: $kind) { Text("Tout").tag(nil as SessionKind?); Text("Cours").tag(Optional(SessionKind.course)); Text("Révisions").tag(Optional(SessionKind.revision)) }.pickerStyle(.segmented)
            Picker("Période", selection: $period) { ForEach(["Jour", "Semaine", "Mois"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            HStack {
                Button("Période précédente", systemImage: "chevron.left") { shift(-1) }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                Spacer(); DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden(); Spacer()
                Button("Période suivante", systemImage: "chevron.right") { shift(1) }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
            AtelierCard {
                Text(kind?.label ?? "Cours et révisions").font(.headline)
                Text(Atelier.duration(displayedTotal)).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                Text(interval.start.cadenceFormatted(date: .abbreviated, time: .omitted) + " – " + interval.end.addingTimeInterval(-1).cadenceFormatted(date: .abbreviated, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                if kind != .revision { Text("Dont \(Atelier.duration(totals.courseEstimated)) de cours estimés.").font(.footnote).foregroundStyle(.secondary) }
            }
            AtelierCard {
                Text("Répartition quotidienne").font(.headline)
                Chart {
                    ForEach(dailyData) { day in
                        if kind != .revision {
                            BarMark(x: .value("Jour", day.date, unit: .day), y: .value("Heures", day.totals.courseMeasured / 3600))
                                .foregroundStyle(by: .value("Suivi", "Cours mesurés / confirmés"))
                            BarMark(x: .value("Jour", day.date, unit: .day), y: .value("Heures", day.totals.courseEstimated / 3600))
                                .foregroundStyle(by: .value("Suivi", "Cours estimés"))
                        }
                        if kind != .course {
                            BarMark(x: .value("Jour", day.date, unit: .day), y: .value("Heures", day.totals.revisions / 3600))
                                .foregroundStyle(by: .value("Suivi", "Révisions"))
                        }
                    }
                }
                .chartForegroundStyleScale(["Cours mesurés / confirmés": Atelier.blue, "Cours estimés": Color.cyan.opacity(0.6), "Révisions": Atelier.revision])
                .chartYAxisLabel("Heures")
                .frame(height: 230)
                .accessibilityLabel("Temps suivi par jour, en heures. Les estimations sont représentées séparément.")
            }
            AtelierCard {
                Text("Qualité du suivi").font(.headline)
                if kind != .revision {
                    MetricRow(title: "Cours mesurés ou confirmés", seconds: totals.courseMeasured)
                    MetricRow(title: "Cours estimés", seconds: totals.courseEstimated, color: .cyan)
                }
                if kind != .course { MetricRow(title: "Révisions", seconds: totals.revisions, color: Atelier.revision) }
                Text("Les créneaux à venir, les absences et les cours ignorés ne sont pas comptés.").font(.caption).foregroundStyle(.secondary)
            }
            if !subjectData.isEmpty {
                AtelierCard {
                    Text("Par matière").font(.headline)
                    ForEach(subjectData, id: \.subject.id) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(item.subject.name); Spacer(); Text(Atelier.duration(item.seconds)).fontWeight(.semibold).monospacedDigit() }.font(.subheadline)
                            ProgressView(value: item.seconds, total: max(1, displayedTotal)).tint(Color(cadenceHex: item.subject.colorHex))
                                .accessibilityLabel(item.subject.name).accessibilityValue(Atelier.duration(item.seconds))
                        }
                    }
                }
            }
            NavigationLink("Consulter les séances") { HistoryView(initialKind: kind) }
        }.navigationTitle("Statistiques")
    }
    private func shift(_ direction: Int) { date = Calendar.current.date(byAdding: component, value: direction, to: date) ?? date }
}

private struct DayTotals: Identifiable {
    let date: Date
    let totals: StudyTotals
    var id: Date { date }
}
