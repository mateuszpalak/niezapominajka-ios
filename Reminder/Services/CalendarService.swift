import Foundation
import EventKit

/// Wydarzenia w Kalendarzu Apple (EventKit).
struct CalendarService {
    /// EKEventStore jest bezpieczny do użycia z wielu wątków (dokumentacja EventKit), a pole jest stałe.
    nonisolated(unsafe) private static let sharedStore = EKEventStore()
    private var store: EKEventStore { Self.sharedStore }

    /// Tworzy wydarzenie (domyślnie 60 min) z alertem 30 min przed. Zwraca identyfikator (do „Cofnij”).
    func addEvent(title: String, notes: String?, start: Date, end: Date? = nil, location: String? = nil,
                  calendarName: String? = nil) async throws -> String {
        guard try await store.requestFullAccessToEvents() else {
            throw NSError(domain: "Reminder", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Brak dostępu do Kalendarza — włącz w Ustawieniach."])
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.location = location
        event.startDate = start
        event.endDate = end.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(3600)
        event.calendar = writableCalendars().first { $0.title == calendarName } ?? store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -30 * 60))
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    /// Usuwa wydarzenie („Cofnij”).
    func remove(id: String) throws {
        guard let event = store.event(withIdentifier: id) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    /// Nazwy kalendarzy, do których można zapisywać.
    func calendarNames() async -> [String] {
        guard (try? await store.requestFullAccessToEvents()) == true else { return [] }
        return writableCalendars().map(\.title).sorted()
    }

    func defaultCalendarName() -> String? {
        store.defaultCalendarForNewEvents?.title
    }

    private func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter(\.allowsContentModifications)
    }

    /// Wydarzenie w formie, którą można bezpiecznie przekazać między wątkami.
    struct EventSummary: Sendable {
        let title: String
        let start: Date
        let isAllDay: Bool
    }

    /// Wydarzenia z danego dnia, posortowane po godzinie rozpoczęcia.
    func events(on day: Date) async throws -> [EventSummary] {
        guard try await store.requestFullAccessToEvents() else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        let predicate = store.predicateForEvents(
            withStart: start, end: start.addingTimeInterval(86_400), calendars: nil)
        // events(matching:) jest synchroniczne — nie blokuj głównego wątku.
        let store = self.store
        return await Task.detached {
            store.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .map { EventSummary(title: $0.title ?? "", start: $0.startDate, isAllDay: $0.isAllDay) }
        }.value
    }
}
