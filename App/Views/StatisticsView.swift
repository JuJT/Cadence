import SwiftUI
import Charts
import CadenceCore

struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var totalFontSize: CGFloat = 52
    @State private var kind: SessionKind?
    @State private var period = "Semaine"
    @State private var date = Date()
    private var component: Calendar.Component { period == "Jour" ? .day : period == "Mois" ? .month : .weekOfYear }
    private var interval: DateInterval { Calendar.current.dateInterval(of: component, for: date)! }

    var body: some View {
        CadenceTimelineView(interval: 30) { now in
            let snapshot = StatisticsSnapshot(state: store.state, interval: interval, kind: kind, now: now)
            AtelierPage {
                CadenceSectionHeader(title: "Votre rythme", subtitle: "Un regard sur le temps consacré à vos matières.")
                filters
                summary(snapshot)
                distribution(snapshot)
                quality(snapshot)
                if !snapshot.subjectData.isEmpty { subjects(snapshot) }
                NavigationLink { HistoryView(initialKind: kind) } label: {
                    AtelierCard {
                        HStack(spacing: 14) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title3).foregroundStyle(Atelier.blue)
                                .frame(width: 42, height: 42)
                                .background(Atelier.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Consulter les séances").font(.headline).foregroundStyle(.primary)
                                Text("Retrouver le détail de votre suivi").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("Statistiques")
    }

    private var filters: some View {
        VStack(spacing: 12) {
            Picker("Type", selection: $kind) {
                Text("Tout").tag(nil as SessionKind?)
                Text("Cours").tag(Optional(SessionKind.course))
                Text("Révisions").tag(Optional(SessionKind.revision))
            }.pickerStyle(.segmented).cadenceSegmentedStyle()
            Picker("Période", selection: $period) {
                ForEach(["Jour", "Semaine", "Mois"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).cadenceSegmentedStyle()
            HStack(spacing: 12) {
                dateButton(previous: true)
                Spacer(minLength: 0)
                DatePicker("Date", selection: $date, displayedComponents: .date).labelsHidden()
                Spacer(minLength: 0)
                dateButton(previous: false)
            }
        }
    }

    private func summary(_ snapshot: StatisticsSnapshot) -> some View {
        AtelierCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind?.label ?? "Cours et révisions").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text(Atelier.duration(snapshot.displayedTotal))
                        .font(.system(size: totalFontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                        .contentTransition(.numericText())
                    Text(period == "Jour" ? "sur cette journée" : period == "Mois" ? "sur ce mois" : "sur cette semaine")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                summaryRing(snapshot)
            }
            Text(snapshot.interval.start.cadenceFormatted(date: .abbreviated, time: .omitted) + " – " + snapshot.interval.end.addingTimeInterval(-1).cadenceFormatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(snapshot.series) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Circle().fill(item.color.gradient).frame(width: 7, height: 7)
                            Text(item.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(Atelier.duration(item.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(item.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private func summaryRing(_ snapshot: StatisticsSnapshot) -> some View {
        ZStack {
            Circle().stroke(Atelier.blue.opacity(0.08), lineWidth: 12)
            if snapshot.displayedTotal > 0 {
                Chart(snapshot.series.filter { $0.seconds > 0 }) { item in
                    SectorMark(angle: .value("Durée", item.seconds), innerRadius: .ratio(0.76), angularInset: 3)
                        .cornerRadius(5).foregroundStyle(item.color.gradient)
                }
            }
            Image(systemName: "chart.pie")
                .font(.system(size: 24, weight: .light)).foregroundStyle(Atelier.blue.opacity(0.7))
        }
        .frame(width: 94, height: 94).padding(5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Répartition du temps suivi, sans objectif imposé")
    }

    private func distribution(_ snapshot: StatisticsSnapshot) -> some View {
        AtelierCard {
            HStack {
                Text("Au fil des jours").font(.headline)
                Spacer()
                Text(snapshot.chartUnit).font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(snapshot.days) { day in
                    if kind != .revision {
                        BarMark(x: .value("Jour", day.date, unit: .day), y: .value(snapshot.chartUnit, day.totals.courses / snapshot.chartDivisor))
                            .cornerRadius(4).foregroundStyle(by: .value("Suivi", "Cours"))
                    }
                    if kind != .course {
                        BarMark(x: .value("Jour", day.date, unit: .day), y: .value(snapshot.chartUnit, day.totals.revisions / snapshot.chartDivisor))
                            .cornerRadius(4).foregroundStyle(by: .value("Suivi", "Révisions"))
                    }
                }
            }
            .chartForegroundStyleScale(["Cours": Atelier.blue, "Révisions": Atelier.revision])
            .chartYScale(domain: 0...max(1, snapshot.maximumDailySeconds / snapshot.chartDivisor * 1.2))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    AxisValueLabel().foregroundStyle(Color.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: period == "Jour" ? 1 : 4)) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 14)
            .frame(height: 210)
            .accessibilityLabel("Temps suivi par jour, en \(snapshot.chartUnit.lowercased()), réparti entre cours et révisions.")
            if snapshot.displayedTotal == 0 {
                Text("Vos séances donneront vie à ce graphique.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func quality(_ snapshot: StatisticsSnapshot) -> some View {
        AtelierCard {
            Label("Votre suivi", systemImage: "checkmark.seal").font(.headline).foregroundStyle(.primary)
            if kind != .revision { MetricRow(title: "Cours", seconds: snapshot.totals.courses) }
            if kind != .course { MetricRow(title: "Révisions", seconds: snapshot.totals.revisions, color: Atelier.revision) }
            Text("Les cours à venir, les absences et les cours retirés ne sont pas comptés.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func subjects(_ snapshot: StatisticsSnapshot) -> some View {
        AtelierCard {
            Text("Vos matières").font(.headline)
            ForEach(snapshot.subjectData, id: \.subject.id) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        SubjectMark(subject: item.subject)
                        Text(item.subject.name).font(.subheadline.weight(.medium))
                        Spacer(minLength: 4)
                        Text(Atelier.duration(item.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    ProgressView(value: item.seconds, total: max(1, snapshot.displayedTotal))
                        .tint(Color(cadenceHex: item.subject.colorHex))
                        .accessibilityLabel(item.subject.name).accessibilityValue(Atelier.duration(item.seconds))
                }.padding(.vertical, 3)
            }
        }
    }

    private func dateButton(previous: Bool) -> some View {
        Button(previous ? "Période précédente" : "Période suivante", systemImage: previous ? "chevron.left" : "chevron.right") { shift(previous ? -1 : 1) }
            .labelStyle(.iconOnly).font(.subheadline.weight(.semibold))
            .frame(width: 44, height: 44).buttonStyle(.plain)
            .background {
                if reduceTransparency { Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)) }
                else { Circle().fill(.thinMaterial) }
            }
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.8))
    }
    private func shift(_ direction: Int) { date = Calendar.current.date(byAdding: component, value: direction, to: date) ?? date }
}

/// Each period and day is aggregated once. Chart cells only read these values.
private struct StatisticsSnapshot {
    let interval: DateInterval
    let totals: StudyTotals
    let displayedTotal: Double
    let days: [DayTotals]
    let subjectData: [(subject: Subject, seconds: Double)]
    let series: [StatisticsSeries]
    let maximumDailySeconds: Double
    let chartDivisor: Double
    let chartUnit: String

    init(state: CadenceState, interval: DateInterval, kind: SessionKind?, now: Date) {
        self.interval = interval
        let selected: (StudyTotals) -> Double = { value in
            kind == .course ? value.courses : kind == .revision ? value.revisions : value.total
        }
        let values = Statistics.bySubject(state: state, in: interval, now: now)
        let totals = values.values.reduce(StudyTotals(), +)
        self.totals = totals
        displayedTotal = selected(totals)
        subjectData = state.subjects.compactMap { subject in
            guard let value = values[subject.id] else { return nil }
            let seconds = selected(value)
            return seconds > 0 ? (subject: subject, seconds: seconds) : nil
        }.sorted { $0.seconds > $1.seconds }
        var days: [DayTotals] = []
        var cursor = interval.start
        while cursor < interval.end {
            let day = Atelier.day(cursor)
            days.append(DayTotals(date: cursor, totals: Statistics.totals(state: state, in: day, now: now)))
            cursor = day.end
        }
        self.days = days
        let maximum = days.map { selected($0.totals) }.max() ?? 0
        maximumDailySeconds = maximum
        chartDivisor = maximum < 3600 ? 60 : 3600
        chartUnit = maximum < 3600 ? "Minutes" : "Heures"
        var series: [StatisticsSeries] = []
        if kind != .revision { series.append(StatisticsSeries(title: "Cours", seconds: totals.courses, color: Atelier.blue)) }
        if kind != .course { series.append(StatisticsSeries(title: "Révisions", seconds: totals.revisions, color: Atelier.revision)) }
        self.series = series
    }
}

private struct DayTotals: Identifiable {
    let date: Date
    let totals: StudyTotals
    var id: Date { date }
}

private struct StatisticsSeries: Identifiable {
    let title: String
    let seconds: Double
    let color: Color
    var id: String { title }
}
