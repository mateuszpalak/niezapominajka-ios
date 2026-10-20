import Foundation

enum CommandAction: String, Codable, CaseIterable {
    case reminder
    case note
    case alarm
    case shopping
    case event
    case message
    case call
    case query
    case complete
}

/// Strukturalna odpowiedź LLM po interpretacji jednego polskiego polecenia.
/// Jedna wypowiedź może dać kilka takich poleceń (patrz `CommandInterpreter`).
struct InterpretedCommand: Codable, Equatable {
    var action: CommandAction
    var title: String
    /// ISO 8601 z offsetem strefy, np. "2026-08-07T20:00:00+02:00".
    var dueDate: String?
    /// Koniec wydarzenia (ISO 8601); null = godzina po `dueDate`.
    var endDate: String?
    var notes: String?
    /// Produkty do dodania na listę zakupów (dla action == .shopping).
    var items: [String]?
    /// Nazwa miejsca dla przypomnienia lokalizacyjnego ("jak będę w Lidlu") albo miejsce wydarzenia.
    var location: String?
    /// Imię/nazwa kontaktu (dla action == .message / .call).
    var recipient: String?
    /// Pytanie doprecyzowujące, gdy pasuje kilka kontaktów („Do której Ani wysłać?”).
    var clarify: String?
    /// Gotowe polskie zdanie do wypowiedzenia przez TTS.
    var confirmation: String

    // Pola uzupełniane lokalnie (domyślne z Ustawień / wybór na karcie) — LLM ich nie zwraca.
    /// Lista Przypomnień (przypomnienie, zakupy) albo „folder” notatki.
    var listName: String?
    /// Kalendarz wydarzenia.
    var calendarName: String?
    /// Etykieta numeru kontaktu („komórka”, „dom”…).
    var phoneLabel: String?

    var dueDateParsed: Date? {
        get { Self.parseDate(dueDate) }
        set { dueDate = newValue.map(Self.isoString) }
    }

    var endDateParsed: Date? {
        get { Self.parseDate(endDate) }
        set { endDate = newValue.map(Self.isoString) }
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string) ?? {
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: string)
        }()
    }

    static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        return f.string(from: date)
    }
}
