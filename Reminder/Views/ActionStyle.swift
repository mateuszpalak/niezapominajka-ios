import SwiftUI

// MARK: - Prezentacja akcji (ikona, kolor, nazwa) — wg designu

extension CommandAction {
    var label: String {
        switch self {
        case .reminder: return "Przypomnienie"
        case .alarm: return "Alarm"
        case .note: return "Notatka"
        case .shopping: return "Lista zakupów"
        case .event: return "Wydarzenie"
        case .message: return "Wiadomość SMS"
        case .call: return "Połączenie"
        case .query: return "Plany"
        case .complete: return "Odhaczone"
        }
    }

    var symbol: String {
        switch self {
        case .reminder: return "clock"
        case .alarm: return "alarm"
        case .note: return "doc.text"
        case .shopping: return "cart"
        case .event: return "calendar"
        case .message: return "message"
        case .call: return "phone"
        case .query: return "list.bullet.rectangle"
        case .complete: return "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .reminder, .alarm: return Color(hex: 0xFF9500)
        case .event: return Color(hex: 0xFF3B30)
        case .note: return Color(hex: 0xE8A800)
        case .shopping: return Color(hex: 0x5856D6)
        case .message, .query: return Color(hex: 0x007AFF)
        case .call, .complete: return Color(hex: 0x34C759)
        }
    }

    /// Bezpieczne akcje zapisują się od razu (z „Cofnij”); SMS i połączenie czekają na odliczanie.
    var isSafe: Bool { self != .message && self != .call }

    /// Czasownik na przycisku dla akcji niebezpiecznej.
    var verb: String { self == .call ? "Zadzwoń" : "Wyślij" }

    /// Status po wykonaniu.
    var doneLabel: String {
        switch self {
        case .message: return "Wysłano"
        case .call: return "Dzwonię…"
        case .query: return "Sprawdzono"
        case .complete: return "Odhaczono"
        default: return "Zapisano"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
