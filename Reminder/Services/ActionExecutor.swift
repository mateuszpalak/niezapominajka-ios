import Foundation
import SwiftData
import UIKit

/// Wykonuje zinterpretowaną akcję: przypomnienie / alarm / notatka.
@MainActor
struct ActionExecutor {
    var modelContext: ModelContext

    /// Wykonuje akcję. Zwraca tekst do wypowiedzenia/pokazania, gdy różni się
    /// od `command.confirmation` (np. odczyt planów dnia).
    @discardableResult
    func execute(_ command: InterpretedCommand) async throws -> String? {
        switch command.action {
        case .reminder:
            try await RemindersService().addReminder(
                title: command.title, notes: command.notes, dueDate: command.dueDateParsed,
                locationName: command.location)
        case .alarm:
            guard let date = command.dueDateParsed else {
                // Alarm bez daty nie ma sensu — zapisz jako przypomnienie bez terminu.
                try await RemindersService().addReminder(title: command.title, notes: command.notes, dueDate: nil)
                return nil
            }
            try await AlarmService().scheduleAlarm(title: command.title, date: date)
            try await RemindersService().addReminder(title: command.title, notes: command.notes, dueDate: date)
        case .note:
            // Notatki Apple nie mają publicznego API — notatki lądują jako pozycje
            // bez terminu na liście „Notatki” w Przypomnieniach (synchronizacja iCloud).
            try await RemindersService().addReminder(
                title: command.title, notes: command.notes, dueDate: nil, listName: "Notatki")
        case .shopping:
            let items = command.items?.filter { !$0.isEmpty } ?? []
            guard !items.isEmpty else {
                try await RemindersService().addReminder(title: command.title, notes: command.notes, dueDate: nil)
                return nil
            }
            try await RemindersService().addShoppingItems(items)
        case .event:
            guard let start = command.dueDateParsed else {
                throw NSError(domain: "Reminder", code: 7,
                              userInfo: [NSLocalizedDescriptionKey: "Nie zrozumiałem terminu wydarzenia — spróbuj podać datę i godzinę."])
            }
            try await CalendarService().addEvent(title: command.title, notes: command.notes, start: start)
        case .message:
            let number = try await ContactsService().phoneNumber(for: recipientOrThrow(command))
            let body = command.notes ?? command.title
            let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            guard let url = URL(string: "sms:\(sanitize(number))&body=\(encoded)") else { return nil }
            await UIApplication.shared.open(url)
        case .call:
            let number = try await ContactsService().phoneNumber(for: recipientOrThrow(command))
            guard let url = URL(string: "tel:\(sanitize(number))") else { return nil }
            await UIApplication.shared.open(url)
        case .query:
            return try await daySummary(for: command.dueDateParsed ?? .now)
        case .complete:
            let title = try await RemindersService().completeReminder(matching: command.title)
            return "Odhaczyłem: \(title)."
        }
        return nil
    }

    /// Buduje polskie podsumowanie przypomnień i wydarzeń na dany dzień.
    private func daySummary(for day: Date) async throws -> String {
        let calendar = Calendar.current
        let endOfDay = calendar.startOfDay(for: day).addingTimeInterval(86_400)
        // Pobieraj przypomnienia i kalendarz równolegle.
        async let remindersTask = RemindersService().incompleteReminders(until: endOfDay)
        async let eventsTask = CalendarService().events(on: day)
        let (reminders, events) = try await (remindersTask, eventsTask)

        let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "pl_PL"))
        var parts: [String] = []

        if reminders.isEmpty {
            parts.append("Nie masz zaległych przypomnień.")
        } else {
            let list = reminders.prefix(10).map { reminder -> String in
                guard let comps = reminder.dueDateComponents, let date = calendar.date(from: comps),
                      comps.hour != nil else { return reminder.title ?? "" }
                return "\(reminder.title ?? "") o \(date.formatted(timeFormat))"
            }
            parts.append("Przypomnienia (\(reminders.count)): \(list.joined(separator: ", ")).")
        }
        if events.isEmpty {
            parts.append("Kalendarz jest pusty.")
        } else {
            let list = events.prefix(10).map { event in
                event.isAllDay ? (event.title ?? "")
                    : "\(event.startDate.formatted(timeFormat)) — \(event.title ?? "")"
            }
            parts.append("Wydarzenia (\(events.count)): \(list.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    private func recipientOrThrow(_ command: InterpretedCommand) throws -> String {
        guard let recipient = command.recipient, !recipient.isEmpty else {
            throw NSError(domain: "Reminder", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "Nie zrozumiałem, do kogo — powtórz z imieniem kontaktu."])
        }
        return recipient
    }

    private func sanitize(_ number: String) -> String {
        number.filter { $0.isNumber || $0 == "+" }
    }

    /// Fallback offline: zapis surowego transkryptu jako draft do późniejszego przetworzenia.
    func saveDraft(transcript: String) {
        modelContext.insert(Note(text: transcript, isDraft: true))
        try? modelContext.save()
    }
}
