#if targetEnvironment(simulator)
import SwiftUI
import WidgetKit

/// A simulator QA surface for the exact widget view components.
/// It does not represent SpringBoard rendering, signed sharing or real user data.
struct WidgetDesignPreviewScreen: View {
    private let entry = WidgetDesignFixtures.entry
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Données de démonstration · composants réels\nLe cadrage système et le partage sont à vérifier sur l’iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("widget.preview.notice")
                    Text("Petit format").font(.headline)
                    HStack(spacing: 12) {
                        WidgetPreviewFrame(width: 164, height: 164) {
                            TodayWidgetView(entry: entry, previewFamily: .systemSmall)
                        }.accessibilityIdentifier("widget.preview.today.small")
                        WidgetPreviewFrame(width: 164, height: 164) {
                            WeekWidgetView(entry: entry, previewFamily: .systemSmall)
                        }.accessibilityIdentifier("widget.preview.week.small")
                    }
                    Text("Moyen format").font(.headline)
                    WidgetPreviewFrame(width: 340, height: 164) {
                        TodayWidgetView(entry: entry, previewFamily: .systemMedium)
                    }.accessibilityIdentifier("widget.preview.today.medium")
                    WidgetPreviewFrame(width: 340, height: 164) {
                        WeekWidgetView(entry: entry, previewFamily: .systemMedium)
                    }.accessibilityIdentifier("widget.preview.week.medium")
                    WidgetPreviewFrame(width: 340, height: 164) {
                        NextCourseWidgetView(entry: entry)
                    }.accessibilityIdentifier("widget.preview.next.medium")
                    Text("Matière longue et absence de partage").font(.headline)
                    HStack(spacing: 12) {
                        WidgetPreviewFrame(width: 164, height: 164) {
                            NextCourseWidgetView(entry: WidgetDesignFixtures.longCourseEntry)
                        }.accessibilityIdentifier("widget.preview.next.long")
                        WidgetPreviewFrame(width: 164, height: 164) {
                            TodayWidgetView(entry: TodayEntry(date: entry.date, snapshot: nil), previewFamily: .systemSmall)
                        }.accessibilityIdentifier("widget.preview.unavailable.small")
                    }
                    Text("Écran verrouillé · composant rectangulaire").font(.headline)
                    WidgetPreviewFrame(width: 188, height: 90) {
                        AccessoryStudyWidgetView(entry: entry, previewFamily: .accessoryRectangular)
                    }.accessibilityIdentifier("widget.preview.accessory.rectangular")
                    Text("Aperçu de composants SwiftUI. Aucun widget n’est installé par cet écran.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 340, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Aperçu des widgets · simulateur")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("widget.preview.screen")
    }
}

private struct WidgetPreviewFrame<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let content: Content
    init(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.content = content()
    }
    var body: some View {
        content
            .padding(16)
            .frame(width: width, height: height)
            .background { WidgetCanvas() }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.06)) }
    }
}

private enum WidgetDesignFixtures {
    static let entry: TodayEntry = {
        let now = Date()
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: now)?.start ?? Calendar.current.startOfDay(for: now)
        let courses = [90.0, 120, 45, 150, 105, 0, 0]
        let revisions = [35.0, 20, 40, 30, 45, 60, 25]
        let days: [WidgetDaySummary] = (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
            let hasHappened = date <= now
            return WidgetDaySummary(date: date, courses: hasHappened ? courses[offset] * 60 : 0,
                revisions: hasHappened ? revisions[offset] * 60 : 0, estimated: hasHappened && offset < 4 ? 1800 : 0)
        }
        let course = WidgetCourseSummary(title: "Anglais", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(6900))
        return TodayEntry(date: now, snapshot: WidgetSnapshot(updatedAt: now, courseMeasured: 9000,
            courseEstimated: 1800, revisions: 2700, activeSubject: "Physique-Chimie",
            activeKind: "Révision", isPaused: false, nextCourseTitle: course.title, nextCourseStart: course.start,
            weekDays: days, topSubjectName: "Mathématiques", upcomingCourses: [course]))
    }()

    static var longCourseEntry: TodayEntry {
        let now = entry.date
        let course = WidgetCourseSummary(title: "Enseignement scientifique et culture générale",
            start: now.addingTimeInterval(3600), end: now.addingTimeInterval(6900))
        return TodayEntry(date: now, snapshot: WidgetSnapshot(updatedAt: now, courseMeasured: 0,
            courseEstimated: 0, revisions: 0, activeSubject: nil, activeKind: nil, isPaused: false,
            nextCourseTitle: course.title, nextCourseStart: course.start, upcomingCourses: [course]))
    }
}
#endif
