import Foundation
import SwiftData
import UIKit

/// SMS do wysłania przez systemowy arkusz Wiadomości.
struct MessageDraft: Identifiable, Equatable {
    let id = UUID()
    var recipients: [String]
    var body: String
}

/// Wynik wykonania akcji.
struct ExecutionResult {
    /// Do „Cofnij”.
    var undo: UndoToken?
    /// Tekst do pokazania/wypowiedzenia (np. odczyt planów dnia).
    var message: String?
    /// SMS czeka na wysłanie w arkuszu Wiadomości.
    var compose: MessageDraft?
}

/// Wykonuje zinterpretowaną akcję: przypomnienie / alarm / notatka / zakupy / wydarzenie / SMS / telefon.
@MainActor
struct ActionExecutor {
    var modelContext: ModelContext

    func execute(_ command: InterpretedCommand, contact: ContactMatch? = nil) async throws -> ExecutionResult {
        switch command.action {
        case .reminder:
            let id = try await RemindersService().addReminder(
                title: command.title, notes: command.notes, dueDate: command.dueDateParsed,
                listName: command.listName, locationName: command.location)
            return ExecutionResult(undo: .reminders([id]))
        case .alarm:
            guard let date = command.dueDateParsed else {
                // Alarm bez daty nie ma sensu — zapisz jako przypomnienie bez terminu.
                let id = try await RemindersService().addReminder(title: command.title, notes: command.notes, dueDate: nil)
                return ExecutionResult(undo: .reminders([id]))
            }
            let alarmID = try await AlarmService().scheduleAlarm(title: command.title, date: date)
            let id = try await RemindersService().addReminder(title: command.title, notes: command.notes, dueDate: date)
            return ExecutionResult(undo: .alarm(alarmID, reminder: id))
        case .note:
            // Notatki Apple nie mają publicznego API — notatki lądują jako pozycje
            // bez terminu na liście „Notatki” w Przypomnieniach (synchronizacja iCloud).
            let id = try await RemindersService().addReminder(
                title: command.title, notes: command.notes, dueDate: nil, listName: command.listName ?? "Notatki")
            return ExecutionResult(undo: .reminders([id]))
        case .shopping:
            let items = command.items?.filter { !$0.isEmpty } ?? []
            guard !items.isEmpty else {
                let id = try await RemindersService().addReminder(
                    title: command.title, notes: command.notes, dueDate: nil, listName: command.listName)
                return ExecutionResult(undo: .reminders([id]))
            }
            let ids = try await RemindersService().addShoppingItems(items, listName: command.listName)
            return ExecutionResult(undo: .reminders(ids))
        case .event:
            guard let start = command.dueDateParsed else {
                throw NSError(domain: "Reminder", code: 7,
                              userInfo: [NSLocalizedDescriptionKey: "Nie zrozumiałem terminu wydarzenia — spróbuj podać datę i godzinę."])
            }
            let id = try await CalendarService().addEvent(
                title: command.title, notes: command.notes, start: start, end: command.endDateParsed,
                location: command.location, calendarName: command.calendarName)
            return ExecutionResult(undo: .event(id))
        case .message:
            let number = try await phoneNumber(command, contact: contact)
            return ExecutionResult(compose: MessageDraft(recipients: [sanitize(number)], body: command.notes ?? command.title))
        case .call:
            let number = try await phoneNumber(command, contact: contact)
            guard let url = URL(string: "tel:\(sanitize(number))") else { return ExecutionResult() }
            await UIApplication.shared.open(url)
            return ExecutionResult()
        case .query:
            return ExecutionResult(message: try await daySummary(for: command.dueDateParsed ?? .now))
        case .complete:
            let (id, title) = try await RemindersService().completeReminder(matching: command.title)
            return ExecutionResult(undo: .completed(id), message: "Odhaczyłem: \(title).")
        }
    }

    /// „Cofnij”: usuwa to, co zapisaliśmy.
    func undo(_ token: UndoToken) throws {
        switch token {
        case .reminders(let ids):
            try RemindersService().remove(ids: ids)
        case .event(let id):
            try CalendarService().remove(id: id)
        case .alarm(let alarmID, let reminderID):
            try? AlarmService().cancelAlarm(id: alarmID)
            try RemindersService().remove(ids: [reminderID])
        case .completed(let id):
            try RemindersService().uncomplete(id: id)
        }
    }

    /// Gdy SMS nie da się wysłać w aplikacji (np. symulator) — otwórz Wiadomości.
    func openMessages(_ draft: MessageDraft) async {
        let encoded = draft.body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let number = draft.recipients.first,
              let url = URL(string: "sms:\(number)&body=\(encoded)") else { return }
        await UIApplication.shared.open(url)
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
                      comps.hour != nil else { return reminder.title }
                return "\(reminder.title) o \(date.formatted(timeFormat))"
            }
            parts.append("Przypomnienia (\(reminders.count)): \(list.joined(separator: ", ")).")
        }
        if events.isEmpty {
            parts.append("Kalendarz jest pusty.")
        } else {
            let list = events.prefix(10).map { event in
                event.isAllDay ? event.title
                    : "\(event.start.formatted(timeFormat)) — \(event.title)"
            }
            parts.append("Wydarzenia (\(events.count)): \(list.joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    private func phoneNumber(_ command: InterpretedCommand, contact: ContactMatch?) async throws -> String {
        if let number = contact?.number(labeled: command.phoneLabel) { return number }
        guard let recipient = command.recipient, !recipient.isEmpty else {
            throw NSError(domain: "Reminder", code: 8,
                          userInfo: [NSLocalizedDescriptionKey: "Nie zrozumiałem, do kogo — powtórz z imieniem kontaktu."])
        }
        let match = try await ContactsService().bestMatch(for: recipient)
        return match.number(labeled: command.phoneLabel) ?? ""
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
