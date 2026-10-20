import Foundation

/// Ustawienia działania (UserDefaults; widok używa tych samych kluczy przez @AppStorage).
enum AppSettings {
    enum Key {
        static let listenOnOpen = "listenOnOpen"
        static let preview = "previewBeforeExecute"
        static let autoExecute = "autoExecute"          // "off" / "3" / "5"
        static let defaultCalendar = "defaultCalendar"  // "" = domyślny systemowy
        static let defaultShoppingList = "defaultShoppingList"  // "" = wykryj listę zakupów
    }

    static func register() {
        UserDefaults.standard.register(defaults: [
            Key.listenOnOpen: true,
            Key.preview: false,
            Key.autoExecute: "3",
            Key.defaultCalendar: "",
            Key.defaultShoppingList: "",
        ])
    }

    static var listenOnOpen: Bool { UserDefaults.standard.bool(forKey: Key.listenOnOpen) }
    static var preview: Bool { UserDefaults.standard.bool(forKey: Key.preview) }

    /// Czas odliczania przed wysłaniem SMS / połączeniem; nil = wyłączone.
    static var autoExecuteSeconds: Double? {
        Double(UserDefaults.standard.string(forKey: Key.autoExecute) ?? "3")
    }

    static var defaultCalendar: String? {
        UserDefaults.standard.string(forKey: Key.defaultCalendar).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var defaultShoppingList: String? {
        UserDefaults.standard.string(forKey: Key.defaultShoppingList).flatMap { $0.isEmpty ? nil : $0 }
    }
}
