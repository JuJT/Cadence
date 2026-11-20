import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    private let previewFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    init(entry: TodayEntry, previewFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = previewFamily
    }
    var body: some View {
        Group {
            if let value = entry.todaySnapshot {
                VStack(alignment: .leading, spacing: 7) {
                    WidgetHeading(title: "Aujourd’hui", symbol: "sun.max")
                    if family == .systemMedium {
                        HStack(alignment: .center, spacing: 18) {
                            total(value).frame(maxWidth: .infinity, alignment: .leading)
                            metrics(value).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let subject = value.activeSubject {
                            Label((value.isPaused ? "En pause · " : "En cours · ") + subject,
                                  systemImage: value.isPaused ? "pause.circle" : "timer")
                                .font(.caption).lineLimit(1).minimumScaleFactor(0.85)
                        }
                    } else {
                        total(value)
                        metrics(value)
                    }
                    Spacer(minLength: 0)
                    SnapshotStamp(date: value.updatedAt)
                }
            } else {
                WidgetUnavailable(title: "Aujourd’hui", symbol: "sun.max", lastUpdate: entry.snapshot?.updatedAt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "cadence://statistiques"))
    }

    private func total(_ value: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(CompactDuration.text(value.courseMeasured + value.courseEstimated + value.revisions))
                .font(.system(size: family == .systemSmall ? 28 : 36, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.75)
            if family == .systemMedium {
                Text("Temps d’étude").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func metrics(_ value: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 7) {
            WidgetMetric(title: "Cours", value: value.courseMeasured + value.courseEstimated, color: WidgetPalette.blue)
            WidgetMetric(title: "Révisions", value: value.revisions, color: WidgetPalette.violet)
        }.font(.caption2)
    }
}

enum WidgetPalette {
    static let blue = Color(red: 0.22, green: 0.48, blue: 0.88)
    static let violet = Color(red: 0.49, green: 0.44, blue: 0.81)
}

struct WidgetCanvas: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
            ? [Color(red: 0.10, green: 0.15, blue: 0.23), Color(red: 0.06, green: 0.09, blue: 0.16)]
            : [Color(red: 0.95, green: 0.98, blue: 1), Color(red: 0.85, green: 0.92, blue: 0.99)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension TodayEntry {
    var todaySnapshot: WidgetSnapshot? {
        guard let snapshot, Calendar.current.isDate(snapshot.updatedAt, inSameDayAs: date) else { return nil }
        return snapshot
    }
    var weekSnapshot: WidgetSnapshot? {
        guard let snapshot, let week = Calendar.current.dateInterval(of: .weekOfYear, for: date),
              week.contains(snapshot.updatedAt), snapshot.weekDays?.count == 7 else { return nil }
        return snapshot
    }
    var upcomingCourse: WidgetCourseSummary? {
        snapshot?.upcomingCourses?.filter { $0.end > date }.sorted { $0.start < $1.start }.first
    }
}

struct WidgetHeading: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(WidgetPalette.blue)
        .lineLimit(1).minimumScaleFactor(0.85)
    }
}

struct SnapshotStamp: View {
    let date: Date
    private var formattedDate: String {
        let locale = Locale(identifier: "fr_FR")
        if Calendar.current.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute().locale(locale))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }
    var body: some View {
        Text("Actualisé " + formattedDate)
            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
    }
}

struct GradeWidgetView: View {
    let entry: TodayEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeading(title: "Ma moyenne", symbol: "chart.bar.fill")
            Spacer(minLength: 2)
            if let grade = entry.snapshot?.grade {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(grade.points.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...2))))
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                    Text("/20").font(.subheadline).foregroundStyle(.secondary)
                }
                if grade.estimated { Text("Indicative").font(.caption.weight(.semibold)).foregroundStyle(WidgetPalette.blue) }
                if let period = grade.period { Text(period).font(.caption).lineLimit(1) }
                Spacer(minLength: 0)
                SnapshotStamp(date: grade.updatedAt)
            } else {
                Text(entry.snapshot == nil ? "Relier mes données" : "Moyenne indisponible").font(.headline)
                Text("Ouvrir mes notes").font(.caption).foregroundStyle(WidgetPalette.blue)
                Spacer(minLength: 0)
            }
        }
        .privacySensitive()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "cadence://notes"))
    }
}

struct HomeworkWidgetView: View {
    let entry: TodayEntry
    private static let deadlineFormat: Date.FormatStyle = .init(locale: Locale(identifier: "fr_FR"),
        timeZone: TimeZone(identifier: "Europe/Paris") ?? .current)
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeading(title: "Mes devoirs", symbol: "checklist")
            Spacer(minLength: 2)
            if let value = entry.snapshot?.homework, let snapshotDate = entry.snapshot?.updatedAt,
               Calendar.current.isDate(snapshotDate, inSameDayAs: entry.date) {
                Text(value.upcomingCount == 0 && value.overdueCount == 0 ? "À jour" : "\(value.upcomingCount) à venir")
                    .font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.78)
                    .accessibilityLabel(value.upcomingCount == 0 ? "Aucun devoir à venir" : "\(value.upcomingCount) devoirs à venir")
                if let subject = value.nextSubject, let due = value.nextDeadline {
                    Text(subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(due.formatted(Self.deadlineFormat.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if value.overdueCount > 0 { Text("\(value.overdueCount) en retard").font(.caption).foregroundStyle(.orange) }
                Spacer(minLength: 0)
                SnapshotStamp(date: value.updatedAt)
            } else {
                Text("Actualiser mes devoirs").font(.headline)
                Text("Ouvrir Cadenza").font(.caption).foregroundStyle(WidgetPalette.blue)
                Spacer(minLength: 0)
            }
        }
        .privacySensitive()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "cadence://devoirs"))
    }
}

struct WidgetMetric: View {
    let title: String
    let value: Double
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 3)
            Text(CompactDuration.text(value)).fontWeight(.medium).monospacedDigit()
        }.lineLimit(1).minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }
}

struct WidgetUnavailable: View {
    let title: String
    let symbol: String
    let lastUpdate: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(title: title, symbol: symbol)
            Spacer(minLength: 0)
            Text(lastUpdate == nil ? "Relier mes données" : "Actualiser mes données")
                .font(.headline).lineLimit(2).minimumScaleFactor(0.85)
            Text("Ouvrir Cadenza").font(.caption).foregroundStyle(WidgetPalette.blue)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityLabel(title + ". Données indisponibles. Ouvrir Cadenza pour vérifier le partage et actualiser.")
    }
}

struct WeekWidgetView: View {
    let entry: TodayEntry
    private let previewFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    init(entry: TodayEntry, previewFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = previewFamily
    }
    var body: some View {
        Group {
            if let snapshot = entry.weekSnapshot, let days = snapshot.weekDays {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        WidgetHeading(title: "Ma semaine", symbol: "chart.bar.xaxis")
                        Spacer(minLength: 4)
                        if family == .systemMedium { weekTotal(days) }
                    }
                    if family == .systemSmall { weekTotal(days) }
                    WeekMiniBars(days: days).frame(maxHeight: .infinity)
                    if family == .systemMedium, let name = snapshot.topSubjectName {
                        Text("Matière la plus travaillée · " + name)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    HStack(spacing: 8) {
                        legend("Cours", color: WidgetPalette.blue)
                        legend("Révisions", color: WidgetPalette.violet)
                    }
                    SnapshotStamp(date: snapshot.updatedAt)
                }
            } else {
                WidgetUnavailable(title: "Ma semaine", symbol: "chart.bar.xaxis", lastUpdate: entry.snapshot?.updatedAt)
            }
        }
        .widgetURL(URL(string: "cadence://statistiques"))
    }
    private func weekTotal(_ days: [WidgetDaySummary]) -> some View {
        let seconds: Double = days.reduce(0.0) { $0 + $1.measured + $1.estimated }
        let duration: String = CompactDuration.text(seconds)
        return Text(duration)
            .font(.system(size: family == .systemSmall ? 23 : 22, weight: .semibold, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.75)
            .accessibilityLabel("Temps d’étude cette semaine : " + duration)
    }
    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 3) { Circle().fill(color).frame(width: 4, height: 4); Text(title) }
            .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
    }
}

struct WeekMiniBars: View {
    let days: [WidgetDaySummary]
    private var peak: Double { max(1, days.map { $0.measured + $0.estimated }.max() ?? 0) }
    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(days) { day in
                WeekWidgetDayBar(day: day, peak: peak)
            }
        }
    }
}

private struct WeekWidgetDayBar: View {
    let day: WidgetDaySummary
    let peak: Double
    private let dayLabel: String
    private let accessibilitySummary: String

    init(day: WidgetDaySummary, peak: Double) {
        self.day = day
        self.peak = peak
        let locale = Locale(identifier: "fr_FR")
        dayLabel = day.date.formatted(.dateTime.weekday(.narrow).locale(locale))
        let fullDay = day.date.formatted(.dateTime.weekday(.wide).locale(locale))
        let courses = "cours " + CompactDuration.text(day.courses + day.estimated)
        let revisions = "révisions " + CompactDuration.text(day.revisions)
        accessibilitySummary = [fullDay, courses, revisions].joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { proxy in
                WeekWidgetBarSegments(day: day, peak: peak, height: proxy.size.height)
            }
            Text(dayLabel).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }
}

private struct WeekWidgetBarSegments: View {
    private let revisionHeight: CGFloat
    private let courseHeight: CGFloat

    init(day: WidgetDaySummary, peak: Double, height: CGFloat) {
        let denominator: Double = max(1, peak)
        let revisionRatio: Double = max(0, day.revisions) / denominator
        let courseRatio: Double = max(0, day.courses + day.estimated) / denominator
        revisionHeight = height * CGFloat(revisionRatio)
        courseHeight = height * CGFloat(courseRatio)
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(WidgetPalette.violet).frame(height: revisionHeight)
            Rectangle().fill(WidgetPalette.blue).frame(height: courseHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct NextCourseWidgetView: View {
    let entry: TodayEntry
    private var heading: String {
        guard let course = entry.upcomingCourse else { return "Prochain cours" }
        return course.start <= entry.date ? "Cours en cours" : "Prochain cours"
    }
    private func emptyMessage(snapshot: WidgetSnapshot, courses: [WidgetCourseSummary]) -> String {
        let isCurrent = Calendar.current.isDate(snapshot.updatedAt, inSameDayAs: entry.date)
        return courses.isEmpty && isCurrent ? "Aucun cours à venir" : "Calendrier à actualiser"
    }
    private func courseDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }
    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let courses = snapshot.upcomingCourses {
                VStack(alignment: .leading, spacing: 4) {
                    WidgetHeading(title: heading, symbol: "calendar")
                    if let course = entry.upcomingCourse {
                        Text(course.title)
                            .font(.headline).lineLimit(2).minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        Text(courseDate(course.start))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(course.start, style: .time)
                            Text("–")
                            Text(course.end, style: .time)
                        }.font(.subheadline.weight(.medium)).foregroundStyle(WidgetPalette.blue).monospacedDigit()
                    } else {
                        Text(emptyMessage(snapshot: snapshot, courses: courses))
                            .font(.headline).lineLimit(2)
                        Text("Ouvrir mes cours").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    SnapshotStamp(date: snapshot.updatedAt)
                }
            } else {
                WidgetUnavailable(title: "Prochain cours", symbol: "calendar", lastUpdate: entry.snapshot?.updatedAt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "cadence://cours"))
    }
}

struct AccessoryStudyWidgetView: View {
    let entry: TodayEntry
    private let previewFamily: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    init(entry: TodayEntry, previewFamily: WidgetFamily? = nil) {
        self.entry = entry
        self.previewFamily = previewFamily
    }
    var body: some View {
        Group {
            if let value = entry.todaySnapshot {
                if family == .accessoryInline {
                    Label("Cadenza · " + CompactDuration.text(value.courseMeasured + value.courseEstimated + value.revisions), systemImage: "book.closed")
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(CompactDuration.text(value.courseMeasured + value.courseEstimated + value.revisions)).font(.headline)
                        Text("Cours " + CompactDuration.text(value.courseMeasured + value.courseEstimated) + " · Révisions " + CompactDuration.text(value.revisions))
                            .font(.caption).lineLimit(2).minimumScaleFactor(0.85)
                    }
                }
            } else {
                Label("Ouvrir Cadenza", systemImage: "book.closed")
            }
        }.widgetURL(URL(string: "cadence://statistiques"))
    }
}
