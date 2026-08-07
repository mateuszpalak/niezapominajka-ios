import Foundation

enum CommandAction: String, Codable {
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

/// Strukturalna odpowiedź LLM po interpretacji polskiego polecenia.
struct InterpretedCommand: Codable, Equatable {
    var action: CommandAction
    var title: String
    /// ISO 8601 z offsetem strefy, np. "2026-08-07T20:00:00+02:00".
    var dueDate: String?
    var notes: String?
    /// Produkty do dodania na listę zakupów (dla action == .shopping).
    var items: [String]?
    /// Nazwa miejsca dla przypomnienia lokalizacyjnego ("jak będę w Lidlu").
    var location: String?
    /// Imię/nazwa kontaktu (dla action == .message / .call).
    var recipient: String?
    /// Gotowe polskie zdanie do wypowiedzenia przez TTS.
    var confirmation: String

    var dueDateParsed: Date? {
        guard let dueDate else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: dueDate) ?? {
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: dueDate)
        }()
    }
}
