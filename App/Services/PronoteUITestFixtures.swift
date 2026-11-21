#if targetEnvironment(simulator)
import Foundation
import CadenceCore

/// Entirely synthetic, local data for the isolated --uitesting-school store.
/// No credentials, school URLs or personal information are included.
enum PronoteUITestFixtures {
    static func cache() -> PronotePortalCache {
        let now = Date()
        let calendar = SchoolDateCodec.parisCalendar
        let today = calendar.startOfDay(for: now)
        func date(_ day: Int, hour: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: day, to: today)!
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
        }
        let formatter = ISO8601DateFormatter()
        func timestamp(_ value: Date) -> SchoolJSON { .string(formatter.string(from: value)) }
        func subject(_ name: String) -> SchoolJSON { .object(["name": .string(name)]) }
        func grade(_ points: Double) -> SchoolJSON { .object(["kind": .number(0), "points": .number(points)]) }
        let capabilities = ["grades", "evaluations", "attendance", "news", "discussions", "menus", "contents", "account", "gradebook", "homepage", "compose"]
        let period = PronotePeriod(id: "fixture-period", name: "Période fictive", kind: 0,
                                   startDate: date(-30), endDate: date(60))
        let annual = PronotePeriod(id: "fixture-annual", name: "Année fictive", kind: 0,
                                   startDate: date(-180), endDate: date(180))
        let profile = PronoteProfile(displayName: "Alex Exemple", establishment: "Établissement fictif",
                                     className: "Classe exemple", resourceID: "fixture-student",
                                     resources: [PronoteStudentResource(id: "fixture-student", name: "Alex Exemple", className: "Classe exemple")],
                                     capabilities: capabilities, periods: [annual, period],
                                     defaultPeriodIDs: ["grades": period.id, "attendance": period.id],
                                     sectionPeriodIDs: ["grades": [period.id, annual.id], "attendance": [period.id]])
        var sections: [String: SchoolJSON] = [
            "grades": .object([
                "overallAverage": grade(16.5), "classAverage": grade(14),
                "subjectsAverages": .array([.object([
                    "subject": subject("Mathématiques"), "student": grade(16.5),
                    "class_average": grade(14), "outOf": grade(20)
                ]), .object([
                    "subject": subject("Français"), "student": grade(15), "outOf": grade(20)
                ])]),
                "grades": .array([.object([
                    "id": .string("fixture-equations"),
                    "subject": subject("Mathématiques"), "date": timestamp(date(-2, hour: 10)),
                    "value": grade(16.5), "outOf": grade(20), "coefficient": .number(1),
                    "comment": .string("Évaluation fictive — équations"), "average": grade(14)
                ]), .object([
                    "id": .string("fixture-commentaire"),
                    "subject": subject("Français"), "date": timestamp(date(-3, hour: 11)),
                    "value": grade(15), "outOf": grade(20), "coefficient": .number(2),
                    "comment": .string("Commentaire composé")
                ])])
            ]),
            "evaluations": .object(["evaluations": .array([.object([
                "name": .string("Évaluation fictive des compétences"), "subject": subject("Français"),
                "date": timestamp(date(-1, hour: 9)), "description": .string("Exemple réservé aux tests du simulateur."),
                "levels": .array([.string("En cours"), .string("Acquis")]),
                "skills": .array([.object(["itemName": .string("Comprendre un texte fictif"), "level": .number(1)])])
            ])])]),
            "attendance": .object([
                "absences": .array([.object([
                    "id": .string("fixture-absence"), "startDate": timestamp(date(-3, hour: 8)),
                    "endDate": timestamp(date(-3, hour: 12)), "hoursMissed": .number(4),
                    "minutesMissed": .number(0), "daysMissed": .number(1),
                    "reason": .string("Motif fictif : maladie"), "justified": .bool(true),
                    "administrativelyFixed": .bool(true)
                ])]), "delays": .array([]), "observations": .array([]),
                "punishments": .array([]), "precautionaryMeasures": .array([])
            ]),
            "news": .object(["items": .array([.object([
                "id": .string("fixture-news"), "title": .string("Information fictive de test"),
                "author": .string("Équipe fictive"), "creationDate": timestamp(date(-1, hour: 12)),
                "content": .string("<div>Cette information est entièrement fictive et ne concerne aucun établissement réel.</div>"),
                "read": .bool(true), "needToAcknowledge": .bool(false), "attachments": .array([])
            ])])]),
            "discussions": .object(["items": .array([.object([
                "id": .string("fixture-discussion"),
                "participantsMessageID": .string("fixture-discussion"), "subject": .string("Discussion fictive de test"),
                "creator": .string("Professeur fictif"), "date": timestamp(date(-1, hour: 16)),
                "numberOfMessagesUnread": .number(0), "closed": .bool(true)
            ])])]),
            "recipients": .array([.object([
                "id": .string("fixture-teacher"), "name": .string("Enseignant fictif"),
                "kind": .number(3), "subjects": .array([]), "isPrincipal": .bool(false)
            ])]),
            "discussion:fixture-discussion": .object([
                "defaultReplyMessageID": .string("fixture-sent-message"),
                "drafts": .array([]), "canIncludeStudentsAndParents": .bool(false),
                "sents": .array([.object([
                "id": .string("fixture-sent-message"), "replyMessageID": .string("fixture-reply"),
                "transferredMessages": .array([]), "partialVisibility": .bool(false),
                "amountOfRecipients": .number(1),
                "author": .object(["name": .string("Professeur fictif")]),
                "creationDate": timestamp(date(-1, hour: 16)),
                "content": .string("Message fictif : pensez à relire la leçon."), "files": .array([])
            ])])]),
            "menus": .object(["days": .array([.object([
                "date": timestamp(date(0)), "lunch": .object([
                    "name": .string("Déjeuner fictif"),
                    "entry": .array([.object(["name": .string("Salade exemple"), "allergens": .array([]), "labels": .array([])])]),
                    "main": .array([.object(["name": .string("Plat exemple"), "allergens": .array([]), "labels": .array([])])]),
                    "dessert": .array([.object(["name": .string("Fruit exemple"), "allergens": .array([]), "labels": .array([])])])
                ])
            ])])]),
            "contents": .object(["yearStart": timestamp(date(-72)), "resources": .array([.object([
                "id": .string("fixture-resource"), "subject": subject("Mathématiques"),
                "startDate": timestamp(date(0, hour: 10)), "teachers": .array([.string("Professeur fictif")])
            ]), .object([
                "id": .string("fixture-resource-ancien"), "subject": subject("Mathématiques"),
                "startDate": timestamp(date(-62, hour: 9)), "teachers": .array([.string("Professeur fictif")]),
                "contents": .array([.object(["title": .string("Première leçon fictive")])])
            ])])]),
            "resource:fixture-resource": .object([
                "id": .string("fixture-resource"), "subject": subject("Mathématiques"),
                "startDate": timestamp(date(0, hour: 10)), "teachers": .array([.string("Professeur fictif")]),
                "contents": .array([.object([
                    "title": .string("Leçon fictive : les équations"), "categoryText": .string("Cours fictif"),
                    "description": .string("&lt;div style=&quot;font-family: Arial&quot;&gt;Contenu entièrement fictif : isoler une inconnue puis vérifier la solution.&lt;/div&gt;"),
                    "themes": .array([.string("Algèbre")]), "files": .array([])
                ])])
            ]),
            "account": .object(["city": .string("Ville fictive"), "country": .string("Pays exemple")]),
            "gradebook": .object([
                "message": .string("Bulletin fictif réservé aux tests."),
                "overallAssessments": .array([.object([
                    "name": .string("Appréciation fictive"), "value": .string("Résultats entièrement inventés pour le simulateur.")
                ])]),
                "subjects": .array([.object([
                    "subject": subject("Mathématiques"), "teachers": .array([.string("Professeur fictif")]),
                    "averages": .object(["student": grade(16.5), "classOverall": grade(14)]),
                    "assessments": .array([.string("Appréciation de démonstration fictive.")])
                ])])
            ]),
            "homepage": .object(["links": .array([])])
        ]
        for section in ["grades", "evaluations", "attendance", "gradebook"] {
            sections[section + ":" + period.id] = sections[section]
        }
        return PronotePortalCache(profile: profile, sections: sections,
                                  updatedAt: Dictionary(uniqueKeysWithValues: sections.keys.map { ($0, now) }))
    }
}
#endif
