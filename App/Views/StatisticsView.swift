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
    private var totals: StudyTotals { Statistics.totals(state: store.state, in: interval, now: .now) }
    private var displayedTotal: Double { displayedSeconds(totals) }
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
            let seconds = displayedSeconds(value)
            return seconds > 0 ? (subject, seconds) : nil
        }.sorted { $0.seconds > $1.seconds }
    }
    private var series: [StatisticsSeries] {
        var result: [StatisticsSeries] = []
        if kind != .revision {
            result.append(StatisticsSeries(title: "Cours suivis", seconds: totals.courseMeasured, color: Atelier.blue))
            result.append(StatisticsSeries(title: "Estimés", seconds: totals.courseEstimated, color: Atelier.ice))
        }
        if kind != .course { result.append(StatisticsSeries(title: "Révisions", seconds: totals.revisions, color: Atelier.revision)) }
        return result
    }
    private var maximumDailySeconds: Double { dailyData.map { displayedSeconds($0.totals) }.max() ?? 0 }
    private var chartDivisor: Double { maximumDailySeconds < 3600 ? 60 : 3600 }
    private var chartUnit: String { chartDivisor == 60 ? "Minutes" : "Heures" }

    var body: some View {
        AtelierPage {
            CadenceSectionHeader(title: "Votre rythme", subtitle: "Un regard sur le temps consacré à vos matières.")
            filters
            summary
            distribution
            quality
            if !subjectData.isEmpty { subjects }
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

    private var summary: some View {
        AtelierCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kind?.label ?? "Cours et révisions").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text(Atelier.duration(displayedTotal))
                        .font(.system(size: totalFontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                        .contentTransition(.numericText())
                    Text(period == "Jour" ? "sur cette journée" : period == "Mois" ? "sur ce mois" : "sur cette semaine")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                summaryRing
            }
            Text(interval.start.cadenceFormatted(date: .abbreviated, time: .omitted) + " – " + interval.end.addingTimeInterval(-1).cadenceFormatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(series) { item in
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

    private var summaryRing: some View {
        ZStack {
            Circle().stroke(Atelier.blue.opacity(0.08), lineWidth: 12)
            if displayedTotal > 0 {
                Chart(series.filter { $0.seconds > 0 }) { item in
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

    private var distribution: some View {
        AtelierCard {
            HStack {
                Text("Au fil des jours").font(.headline)
                Spacer()
                Text(chartUnit).font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(dailyData) { day in
                    if kind != .revision {
                        BarMark(x: .value("Jour", day.date, unit: .day), y: .value(chartUnit, day.totals.courseMeasured / chartDivisor))
                            .cornerRadius(4).foregroundStyle(by: .value("Suivi", "Cours suivis"))
                        BarMark(x: .value("Jour", day.date, unit: .day), y: .value(chartUnit, day.totals.courseEstimated / chartDivisor))
                            .cornerRadius(4).foregroundStyle(by: .value("Suivi", "Estimés"))
                    }
                    if kind != .course {
                        BarMark(x: .value("Jour", day.date, unit: .day), y: .value(chartUnit, day.totals.revisions / chartDivisor))
                            .cornerRadius(4).foregroundStyle(by: .value("Suivi", "Révisions"))
                    }
                }
            }
            .chartForegroundStyleScale(["Cours suivis": Atelier.blue, "Estimés": Atelier.ice, "Révisions": Atelier.revision])
            .chartYScale(domain: 0...max(1, maximumDailySeconds / chartDivisor * 1.2))
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
            .accessibilityLabel("Temps suivi par jour, en \(chartUnit.lowercased()). Les estimations sont représentées séparément.")
            if displayedTotal == 0 {
                Text("Vos séances donneront vie à ce graphique.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var quality: some View {
        AtelierCard {
            Label("Un suivi transparent", systemImage: "checkmark.seal")
                .font(.headline).foregroundStyle(.primary)
            if kind != .revision {
                MetricRow(title: "Cours mesurés ou confirmés", seconds: totals.courseMeasured)
                MetricRow(title: "Cours estimés", seconds: totals.courseEstimated, color: Atelier.ice)
            }
            if kind != .course { MetricRow(title: "Révisions", seconds: totals.revisions, color: Atelier.revision) }
            Text("Les estimations restent distinctes du temps mesuré. Les cours à venir, les absences et les cours ignorés ne sont pas comptés.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subjects: some View {
        AtelierCard {
            Text("Vos matières").font(.headline)
            ForEach(subjectData, id: \.subject.id) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        SubjectMark(subject: item.subject)
                        Text(item.subject.name).font(.subheadline.weight(.medium))
                        Spacer(minLength: 4)
                        Text(Atelier.duration(item.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    ProgressView(value: item.seconds, total: max(1, displayedTotal))
                        .tint(Color(cadenceHex: item.subject.colorHex))
                        .accessibilityLabel(item.subject.name).accessibilityValue(Atelier.duration(item.seconds))
                }.padding(.vertical, 3)
            }
        }
    }

    private func dateButton(previous: Bool) -> some View {
        Button(previous ? "Période précédente" : "Période suivante", systemImage: previous ? "chevron.left" : "chevron.right") {
            shift(previous ? -1 : 1)
        }
        .labelStyle(.iconOnly).font(.subheadline.weight(.semibold))
        .frame(width: 44, height: 44).buttonStyle(.plain)
        .background {
            if reduceTransparency { Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)) }
            else { Circle().fill(.thinMaterial) }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.8))
    }
    private func displayedSeconds(_ value: StudyTotals) -> Double {
        kind == .course ? value.courseMeasured + value.courseEstimated : kind == .revision ? value.revisions : value.total
    }
    private func shift(_ direction: Int) { date = Calendar.current.date(byAdding: component, value: direction, to: date) ?? date }
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
