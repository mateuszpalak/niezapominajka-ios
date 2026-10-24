import Foundation
import EventKit
import CoreLocation
import MapKit

/// Zapis do Przypomnień Apple (EventKit).
struct RemindersService: TaskStore {
    /// Jeden współdzielony magazyn EventKit — tworzenie EKEventStore jest kosztowne.
    /// EKEventStore jest bezpieczny do użycia z wielu wątków (dokumentacja EventKit), a pole jest stałe.
    nonisolated(unsafe) private static let sharedStore = EKEventStore()
    private var store: EKEventStore { Self.sharedStore }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    /// Tworzy przypomnienie na domyślnej liście; z alarmem, jeśli podano termin.
    /// Gdy `listName` podane, zapis idzie na tę listę (tworzy ją, jeśli nie istnieje).
    /// Zwraca identyfikator przypomnienia (do „Cofnij”).
    @discardableResult
    func addTask(title: String, notes: String?, dueDate: Date?, listName: String? = nil,
                 locationName: String? = nil) async throws -> TaskRef {
        guard try await requestAccess() else {
            throw NSError(domain: "Reminder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Brak dostępu do Przypomnień — włącz w Ustawieniach."])
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = try listName.map(calendarNamed) ?? store.defaultCalendarForNewReminders()
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }
        // Przypomnienie lokalizacyjne: geokoduj nazwę miejsca i dodaj alarm geofence
        // (monitoring robi systemowa apka Przypomnienia, nie my).
        if let locationName {
            guard let request = MKGeocodingRequest(addressString: locationName),
                  let item = try await request.mapItems.first else {
                throw NSError(domain: "Reminder", code: 6,
                              userInfo: [NSLocalizedDescriptionKey: "Nie znalazłem miejsca „\(locationName)”."])
            }
            let structured = EKStructuredLocation(title: item.name ?? locationName)
            structured.geoLocation = item.location
            structured.radius = 150
            let alarm = EKAlarm()
            alarm.structuredLocation = structured
            alarm.proximity = .enter
            reminder.addAlarm(alarm)
        }
        try store.save(reminder, commit: true)
        return .apple(reminder.calendarItemIdentifier)
    }

    /// Notatki Apple nie mają publicznego API — notatki lądują jako pozycje
    /// bez terminu na liście „Notatki” w Przypomnieniach (synchronizacja iCloud).
    func addNote(title: String, notes: String?, listName: String) async throws -> TaskRef {
        try await addTask(title: title, notes: notes, dueDate: nil, listName: listName)
    }

    /// Dodaje produkty na listę zakupów użytkownika: podaną `listName` albo wykrytą
    /// („zakupy”/„shopping”; tworzy „Zakupy”, jeśli żadnej nie ma). Zwraca identyfikatory pozycji.
    func addItems(_ items: [String], listName: String? = nil) async throws -> [TaskRef] {
        guard try await requestAccess() else {
            throw NSError(domain: "Reminder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Brak dostępu do Przypomnień — włącz w Ustawieniach."])
        }
        let calendar = try calendarNamed(listName ?? shoppingListName() ?? "Zakupy")
        var ids: [TaskRef] = []
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.title = item
            reminder.calendar = calendar
            try store.save(reminder, commit: false)
            ids.append(.apple(reminder.calendarItemIdentifier))
        }
        try store.commit()
        return ids
    }

    /// Usuwa zapisane wcześniej pozycje („Cofnij”).
    func remove(_ refs: [TaskRef]) throws {
        for case .apple(let id) in refs {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { continue }
            try store.remove(reminder, commit: false)
        }
        try store.commit()
    }

    /// Cofa odhaczenie przypomnienia.
    func uncomplete(_ ref: TaskRef) throws {
        guard case .apple(let id) = ref, let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = false
        try store.save(reminder, commit: true)
    }

    /// Nazwy list Przypomnień (do wyboru na karcie i w Ustawieniach).
    func listNames() async -> [String] {
        guard (try? await requestAccess()) == true else { return [] }
        return store.calendars(for: .reminder).map(\.title).sorted()
    }

    /// Nazwa domyślnej listy Przypomnień.
    func defaultListName() -> String? {
        store.defaultCalendarForNewReminders()?.title
    }

    /// Wykryta lista zakupów („zakupy”/„shopping”).
    func shoppingListName() -> String? {
        TaskMatcher.shoppingList(in: store.calendars(for: .reminder).map(\.title))
    }

    /// Niewykonane przypomnienia z terminem do końca podanego dnia.
    func incompleteTasks(until end: Date) async throws -> [TaskSummary] {
        guard try await requestAccess() else { return [] }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: end, calendars: nil)
        return await fetchSummaries(matching: predicate)
    }

    /// Przypomnienia w formie, którą można bezpiecznie przekazać między wątkami (EKReminder nie jest Sendable).
    private func fetchSummaries(matching predicate: NSPredicate) async -> [TaskSummary] {
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: (reminders ?? []).map {
                    let comps = $0.dueDateComponents
                    return TaskSummary(ref: .apple($0.calendarItemIdentifier), title: $0.title ?? "",
                                       dueDate: comps.flatMap { Calendar.current.date(from: $0) },
                                       hasTime: comps?.hour != nil)
                })
            }
        }
    }

    /// Odhacza pierwsze niewykonane przypomnienie pasujące do frazy; zwraca jego identyfikator i tytuł.
    func complete(matching phrase: String) async throws -> (ref: TaskRef, title: String) {
        guard try await requestAccess() else {
            throw NSError(domain: "Reminder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Brak dostępu do Przypomnień."])
        }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders = await fetchSummaries(matching: predicate)
        guard case .apple(let id)? = TaskMatcher.bestMatch(for: phrase, in: reminders)?.ref,
              let match = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw NSError(domain: "Reminder", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "Nie znalazłem przypomnienia pasującego do „\(phrase)”."])
        }
        match.isCompleted = true
        try store.save(match, commit: true)
        return (.apple(match.calendarItemIdentifier), match.title ?? phrase)
    }

    private func calendarNamed(_ name: String) throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) {
            return existing
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        calendar.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}
