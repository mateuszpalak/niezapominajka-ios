import Foundation
import EventKit
import CoreLocation
import MapKit

/// Zapis do Przypomnień Apple (EventKit).
struct RemindersService {
    /// Jeden współdzielony magazyn EventKit — tworzenie EKEventStore jest kosztowne.
    private static let sharedStore = EKEventStore()
    private var store: EKEventStore { Self.sharedStore }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    /// Tworzy przypomnienie na domyślnej liście; z alarmem, jeśli podano termin.
    /// Gdy `listName` podane, zapis idzie na tę listę (tworzy ją, jeśli nie istnieje).
    /// Zwraca identyfikator przypomnienia (do „Cofnij”).
    @discardableResult
    func addReminder(title: String, notes: String?, dueDate: Date?, listName: String? = nil,
                     locationName: String? = nil) async throws -> String {
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
        return reminder.calendarItemIdentifier
    }

    /// Dodaje produkty na listę zakupów użytkownika: podaną `listName` albo wykrytą
    /// („zakupy”/„shopping”; tworzy „Zakupy”, jeśli żadnej nie ma). Zwraca identyfikatory pozycji.
    func addShoppingItems(_ items: [String], listName: String? = nil) async throws -> [String] {
        guard try await requestAccess() else {
            throw NSError(domain: "Reminder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Brak dostępu do Przypomnień — włącz w Ustawieniach."])
        }
        let calendar = try calendarNamed(listName ?? shoppingListName() ?? "Zakupy")
        var ids: [String] = []
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.title = item
            reminder.calendar = calendar
            try store.save(reminder, commit: false)
            ids.append(reminder.calendarItemIdentifier)
        }
        try store.commit()
        return ids
    }

    /// Usuwa zapisane wcześniej pozycje („Cofnij”).
    func remove(ids: [String]) throws {
        for id in ids {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { continue }
            try store.remove(reminder, commit: false)
        }
        try store.commit()
    }

    /// Cofa odhaczenie przypomnienia.
    func uncomplete(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
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
        store.calendars(for: .reminder).first {
            let t = $0.title.lowercased()
            return t.contains("zakup") || t.contains("shopping")
        }?.title
    }

    /// Niewykonane przypomnienia z terminem do końca podanego dnia.
    func incompleteReminders(until end: Date) async throws -> [EKReminder] {
        guard try await requestAccess() else { return [] }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: end, calendars: nil)
        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
    }

    /// Odhacza pierwsze niewykonane przypomnienie pasujące do frazy; zwraca jego identyfikator i tytuł.
    func completeReminder(matching phrase: String) async throws -> (id: String, title: String) {
        guard try await requestAccess() else {
            throw NSError(domain: "Reminder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Brak dostępu do Przypomnień."])
        }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        let needle = phrase.lowercased()
        let match = reminders.first {
            let title = ($0.title ?? "").lowercased()
            return title.contains(needle) || needle.contains(title)
                || !Set(title.split(separator: " ")).isDisjoint(with: needle.split(separator: " "))
        }
        guard let match else {
            throw NSError(domain: "Reminder", code: 9,
                          userInfo: [NSLocalizedDescriptionKey: "Nie znalazłem przypomnienia pasującego do „\(phrase)”."])
        }
        match.isCompleted = true
        try store.save(match, commit: true)
        return (match.calendarItemIdentifier, match.title ?? phrase)
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
