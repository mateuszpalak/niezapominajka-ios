import Foundation

/// Identyfikatory tego, co zapisaliśmy — pozwalają zrobić „Cofnij”.
enum UndoToken: Equatable {
    case reminders([String])
    case event(String)
    case alarm(UUID, reminder: String)
    case completed(String)
}

/// Jedna karta na ekranie wyniku: polecenie + stan wykonania.
struct PlannedAction: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case running
        case done
        case undone
        case failed(String)
    }

    let id = UUID()
    var command: InterpretedCommand
    var status: Status = .pending
    var undo: UndoToken?
    /// Kontakty pasujące do `recipient` (wybór w dopytywaniu i na karcie).
    var contacts: [ContactMatch] = []
    /// Kilka pasujących kontaktów — trzeba dopytać użytkownika.
    var needsContactChoice = false

    var isSettled: Bool { status != .pending && status != .running }

    /// Kontakt wybrany dla SMS/połączenia.
    var contact: ContactMatch? {
        contacts.first { $0.name == command.recipient } ?? (contacts.count == 1 ? contacts.first : nil)
    }
}

/// Opcje list wyboru na karcie (wczytane z EventKit).
struct ChoiceSource: Equatable {
    var reminderLists: [String] = []
    var calendars: [String] = []
}

/// Pole na karcie (wiersz „etykieta — wartość”), jak `fields` w projekcie designu.
struct CardField: Identifiable, Equatable {
    enum Kind: Equatable {
        case text
        case date
        case choice([String])
        case readOnly
    }

    let key: String
    let label: String
    let value: String
    let kind: Kind
    var id: String { key }
}

extension PlannedAction {
    func fields(_ choices: ChoiceSource = ChoiceSource()) -> [CardField] {
        let c = command
        func choice(_ options: [String], current: String?) -> CardField.Kind {
            var all = options
            if let current, !current.isEmpty, !all.contains(current) { all.insert(current, at: 0) }
            return .choice(all)
        }
        switch c.action {
        case .reminder:
            return [
                CardField(key: "title", label: "Treść", value: c.title, kind: .text),
                CardField(key: "when", label: "Kiedy", value: Self.whenText(c.dueDateParsed), kind: .date),
                CardField(key: "list", label: "Lista", value: c.listName ?? "", kind: choice(choices.reminderLists, current: c.listName)),
            ] + (c.location.map { [CardField(key: "location", label: "Miejsce", value: $0, kind: .text)] } ?? [])
        case .alarm:
            return [
                CardField(key: "title", label: "Treść", value: c.title, kind: .text),
                CardField(key: "when", label: "Kiedy", value: Self.whenText(c.dueDateParsed), kind: .date),
            ]
        case .note:
            return [
                CardField(key: "title", label: "Treść", value: c.title, kind: .text),
                CardField(key: "list", label: "Folder", value: c.listName ?? "", kind: choice(choices.reminderLists, current: c.listName)),
            ]
        case .shopping:
            return [
                CardField(key: "items", label: "Produkty", value: (c.items ?? [c.title]).joined(separator: ", "), kind: .text),
                CardField(key: "list", label: "Lista", value: c.listName ?? "", kind: choice(choices.reminderLists, current: c.listName)),
            ]
        case .event:
            return [
                CardField(key: "title", label: "Tytuł", value: c.title, kind: .text),
                CardField(key: "when", label: "Kiedy", value: Self.rangeText(c.dueDateParsed, c.endDateParsed), kind: .date),
                CardField(key: "location", label: "Miejsce", value: c.location ?? "", kind: .text),
                CardField(key: "calendar", label: "Kalendarz", value: c.calendarName ?? "", kind: choice(choices.calendars, current: c.calendarName)),
            ]
        case .message:
            return [
                recipientField,
                CardField(key: "body", label: "Treść", value: c.notes ?? c.title, kind: .text),
            ]
        case .call:
            return [
                recipientField,
                CardField(key: "number", label: "Numer", value: c.phoneLabel ?? "",
                          kind: choice(contact?.numbers.map(\.label) ?? [], current: c.phoneLabel)),
            ]
        case .query:
            return [
                CardField(key: "title", label: "Pytanie", value: c.title, kind: .readOnly),
                CardField(key: "answer", label: "Plany", value: c.notes ?? "", kind: .readOnly),
            ]
        case .complete:
            return [CardField(key: "title", label: "Zadanie", value: c.title, kind: .readOnly)]
        }
    }

    private var recipientField: CardField {
        let names = contacts.map(\.name)
        return CardField(key: "recipient", label: "Do", value: command.recipient ?? "",
                         kind: names.count > 1 ? .choice(names) : .text)
    }

    /// Tytuł karty = wartość pierwszego pola (jak w designie).
    var cardTitle: String {
        let value = fields().first?.value ?? command.title
        return value.isEmpty ? command.title : value
    }

    /// Podpis w historii „Ostatnio”: „Przypomnienie · Jutro, 15:00”.
    func historyDetail(label: String) -> String {
        let f = fields()
        guard f.count > 1, !f[1].value.isEmpty else { return label }
        return "\(label) · \(f[1].value)"
    }

    mutating func setText(_ key: String, _ value: String) {
        switch key {
        case "title": command.title = value
        case "items":
            command.items = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case "list": command.listName = value
        case "calendar": command.calendarName = value
        case "location": command.location = value.isEmpty ? nil : value
        case "body": command.notes = value
        case "number": command.phoneLabel = value
        case "recipient":
            command.recipient = value
            if let match = contacts.first(where: { $0.name == value }) {
                command.phoneLabel = match.numbers.first?.label
            }
        default: break
        }
    }

    /// Zmienia termin; dla wydarzenia zachowuje czas trwania.
    mutating func setDate(_ date: Date?) {
        var duration: TimeInterval = 3600
        if let start = command.dueDateParsed, let end = command.endDateParsed { duration = end.timeIntervalSince(start) }
        command.dueDateParsed = date
        if command.action == .event, let date {
            command.endDateParsed = date.addingTimeInterval(duration)
        }
    }

    // MARK: - Formatowanie terminów („Jutro, 15:00”, „Piątek, 12:00–13:00”)

    static func whenText(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Bez terminu" }
        return "\(dayText(date, now: now)), \(timeText(date))"
    }

    static func rangeText(_ start: Date?, _ end: Date?, now: Date = .now) -> String {
        guard let start else { return "Bez terminu" }
        let end = end ?? start.addingTimeInterval(3600)
        return "\(dayText(start, now: now)), \(timeText(start))–\(timeText(end))"
    }

    private static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "H:mm"
        return f.string(from: date)
    }

    private static func dayText(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Dziś"
        case 1: return "Jutro"
        case 2: return "Pojutrze"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "pl_PL")
            f.dateFormat = (2..<7).contains(days) ? "EEEE" : "d MMMM"
            let text = f.string(from: date)
            return text.prefix(1).uppercased() + text.dropFirst()
        }
    }
}
