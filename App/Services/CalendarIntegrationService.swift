import Foundation
import EventKit
import CadenceCore

struct CalendarSource: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
}

/// Accès EventKit intégral demandé par iOS, utilisé en lecture uniquement.
/// Cette classe n'appelle aucune API de création, modification ou suppression.
@MainActor
final class CalendarIntegrationService {
    private let eventStore = EKEventStore()

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var permissionDescription: String {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return "Calendrier autorisé · lecture uniquement dans Cadence"
        case .denied: return "Accès refusé. Les séances manuelles restent disponibles."
        case .restricted: return "Accès restreint par les réglages de cet appareil."
        case .writeOnly: return "La lecture nécessite l’accès intégral au calendrier."
        case .notDetermined: return "Calendrier non lié"
        @unknown default: return "Autorisation Calendrier à vérifier"
        }
    }

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func sources() -> [CalendarSource] {
        guard hasAccess else { return [] }
        return eventStore.calendars(for: .event).map {
            CalendarSource(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func events(calendarIDs: Set<String>, window: DateInterval) throws -> [CalendarEvent] {
        guard hasAccess else { throw CalendarAccessError.denied }
        let calendars = eventStore.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        // Un tableau vide ne doit jamais se transformer en « tous les calendriers ».
        guard !calendars.isEmpty else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
        return eventStore.events(matching: predicate).compactMap { event in
            guard let start = event.startDate, let end = event.endDate, end > start,
                  event.status != .canceled else { return nil }
            return CalendarEvent(
                calendarIdentifier: event.calendar.calendarIdentifier,
                eventIdentifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                externalIdentifier: event.calendarItemExternalIdentifier,
                occurrenceAnchor: event.occurrenceDate,
                calendarName: event.calendar.title,
                title: event.title ?? "Cours sans titre",
                start: start, end: end, isAllDay: event.isAllDay,
                isRecurring: event.hasRecurrenceRules || event.occurrenceDate != nil || event.isDetached
            )
        }.sorted { $0.start < $1.start }
    }
}

private enum CalendarAccessError: LocalizedError {
    case denied
    var errorDescription: String? { "Autorisez Calendrier dans Réglages pour lire l’emploi du temps. Les cours et révisions manuels restent disponibles." }
}
