#if targetEnvironment(simulator)
import Foundation
import CadenceCore

/// Synthetic school data for the isolated --uitesting-school store only.
/// This file is excluded from physical-device executables.
enum SchoolUITestFixtures {
    static func populate(_ state: inout CadenceState) {
        let now = Date()
        let calendar = SchoolDateCodec.parisCalendar
        let today = calendar.startOfDay(for: now)
        func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: day, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }
        // Keep the 08:00 lesson in the past even when CI runs overnight.
        let pastDay = now >= date(0, hour: 9) ? 0 : -1
        let snapshot = SchoolSnapshot(
            generatedAt: now,
            timetable: [
                SchoolTimetableEvent(eventID: "fixture-lesson-french-past", startAt: date(pastDay, hour: 8),
                    endAt: date(pastDay, hour: 9), subjectName: "Français", teacherNames: ["Professeur fictif"],
                    classrooms: ["Salle exemple"], lessonResourceID: "fixture-resource-french"),
                SchoolTimetableEvent(eventID: "fixture-lesson-math-future", startAt: date(1, hour: 10),
                    endAt: date(1, hour: 11), subjectName: "Mathématiques", teacherNames: ["Professeur fictif"],
                    classrooms: ["Salle exemple"])
            ],
            homework: [
                SchoolHomework(uid: "fixture-homework-math-today", subject: "Mathématiques", deadline: date(0),
                    description: "<div style=\"font-family: Arial\">Exemple fictif : résoudre deux équations et vérifier les résultats.&nbsp;</div>",
                    difficulty: .string("Exemple de difficulté"), lengthMinutes: 20,
                    attachmentNames: .array([.string("exercices-fictifs.pdf")]), sourceUpdatedAt: now, syncedAt: now),
                SchoolHomework(uid: "fixture-homework-english-tomorrow", subject: "Anglais", deadline: date(1),
                    description: "Exemple fictif : préparer cinq phrases sur un voyage imaginaire.",
                    lengthMinutes: 15, sourceUpdatedAt: now, syncedAt: now),
                SchoolHomework(uid: "fixture-homework-svt-overdue", subject: "SVT", deadline: date(-1),
                    description: "Exemple fictif : revoir le schéma d’une cellule végétale.",
                    lengthMinutes: 10, sourceUpdatedAt: now, syncedAt: now),
                SchoolHomework(uid: "fixture-homework-french-done", subject: "Français", deadline: date(-2),
                    description: "Exemple fictif : rédiger un court résumé de lecture.", done: true,
                    lengthMinutes: 10, sourceUpdatedAt: now, syncedAt: now)
            ],
            courseContent: [
                SchoolCourseContent(resourceID: "fixture-resource-french", contentID: "fixture-content-french",
                    title: "Lecture — exemple fictif", description: "&lt;div&gt;Contenu pédagogique fictif réservé aux tests du simulateur.&lt;/div&gt;")
            ],
            syncState: SchoolSyncState(lastTimetableSync: now, lastHomeworkSync: now, lastContentSync: now),
            windowStart: date(-30), windowEnd: date(31)
        )
        do { try SchoolReconciler.sync(state: &state, snapshot: snapshot, now: now) }
        catch { preconditionFailure("The synthetic school UI fixture must pass model validation.") }
        state.settings.onboardingCompleted = true
        state.settings.defaultSubjectID = state.subjects.first { $0.name == "Mathématiques" && !$0.isArchived }?.id
    }
}
#endif
