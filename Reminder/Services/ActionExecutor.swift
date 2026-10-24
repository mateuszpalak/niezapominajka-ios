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
        let tasks = AppSettings.taskStore
        switch command.action {
        case .reminder:
            let ref = try await tasks.addTask(
                title: command.title, notes: command.notes, dueDate: command.dueDateParsed,
                listName: command.listName, locationName: command.location)
            return ExecutionResult(undo: .tasks([ref]))
        case .alarm:
            guard let date = command.dueDateParsed else {
                // Alarm bez daty nie ma sensu — zapisz jako przypomnienie bez terminu.
                let ref = try await tasks.addTask(title: command.title, notes: command.notes, dueDate: nil,
                                                  listName: nil, locationName: nil)
                return ExecutionResult(undo: .tasks([ref]))
            }
            let alarmID = try await AlarmService().scheduleAlarm(title: command.title, date: date)
            let ref = try await tasks.addTask(title: command.title, notes: command.notes, dueDate: date,
                                              listName: nil, locationName: nil)
            return ExecutionResult(undo: .alarm(alarmID, task: ref))
        case .note:
            let ref = try await tasks.addNote(
                title: command.title, notes: command.notes, listName: command.listName ?? "Notatki")
            return ExecutionResult(undo: .tasks([ref]))
        case .shopping:
            let items = command.items?.filter { !$0.isEmpty } ?? []
            guard !items.isEmpty else {
                let ref = try await tasks.addTask(
                    title: command.title, notes: command.notes, dueDate: nil, listName: command.listName, locationName: nil)
                return ExecutionResult(undo: .tasks([ref]))
            }
            let refs = try await tasks.addItems(items, listName: command.listName)
            return ExecutionResult(undo: .tasks(refs))
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
            let (ref, title) = try await tasks.complete(matching: command.title)
            return ExecutionResult(undo: .completed(ref), message: "Odhaczyłem: \(title).")
        }
    }

    /// „Cofnij”: usuwa to, co zapisaliśmy.
    func undo(_ token: UndoToken) async throws {
        switch token {
        case .tasks(let refs):
            try await refs.first?.store.remove(refs)
        case .event(let id):
            try CalendarService().remove(id: id)
        case .alarm(let alarmID, let ref):
            try? AlarmService().cancelAlarm(id: alarmID)
            try await ref.store.remove([ref])
        case .completed(let ref):
            try await ref.store.uncomplete(ref)
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
        async let remindersTask = AppSettings.taskStore.incompleteTasks(until: endOfDay)
        async let eventsTask = CalendarService().events(on: day)
        let (reminders, events) = try await (remindersTask, eventsTask)

        let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "pl_PL"))
        var parts: [String] = []

        if reminders.isEmpty {
            parts.append("Nie masz zaległych przypomnień.")
        } else {
            let list = reminders.prefix(10).map { reminder -> String in
                guard let date = reminder.dueDate, reminder.hasTime else { return reminder.title }
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
