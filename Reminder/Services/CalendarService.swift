import Foundation
import EventKit

/// Wydarzenia w Kalendarzu Apple (EventKit).
struct CalendarService {
    private static let sharedStore = EKEventStore()
    private var store: EKEventStore { Self.sharedStore }

    /// Tworzy wydarzenie (domyślnie 60 min) z alertem 30 min przed.
    func addEvent(title: String, notes: String?, start: Date, durationMinutes: Int = 60) async throws {
        guard try await store.requestFullAccessToEvents() else {
            throw NSError(domain: "Reminder", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Brak dostępu do Kalendarza — włącz w Ustawieniach."])
        }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -30 * 60))
        try store.save(event, span: .thisEvent, commit: true)
    }

    /// Wydarzenia z danego dnia, posortowane po godzinie rozpoczęcia.
    func events(on day: Date) async throws -> [EKEvent] {
        guard try await store.requestFullAccessToEvents() else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        let predicate = store.predicateForEvents(
            withStart: start, end: start.addingTimeInterval(86_400), calendars: nil)
        // events(matching:) jest synchroniczne — nie blokuj głównego wątku.
        let store = self.store
        return await Task.detached {
            store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        }.value
    }
}
