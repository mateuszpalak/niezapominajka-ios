import Foundation

/// Ustawienia działania (UserDefaults; widok używa tych samych kluczy przez @AppStorage).
enum AppSettings {
    enum Key {
        static let listenOnOpen = "listenOnOpen"
        static let preview = "previewBeforeExecute"
        static let autoExecute = "autoExecute"          // "off" / "3" / "5"
        static let defaultCalendar = "defaultCalendar"  // "" = domyślny systemowy
        static let defaultShoppingList = "defaultShoppingList"  // "" = wykryj listę zakupów
        static let taskDestination = "taskDestination"  // TaskDestination.rawValue
        static let tickTickShoppingList = "tickTickShoppingList"  // jak defaultShoppingList, dla TickTick
    }

    static func register() {
        UserDefaults.standard.register(defaults: [
            Key.listenOnOpen: true,
            Key.preview: false,
            Key.autoExecute: "3",
            Key.defaultCalendar: "",
            Key.defaultShoppingList: "",
            Key.taskDestination: TaskDestination.apple.rawValue,
            Key.tickTickShoppingList: "",
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

    /// Lista zakupów z Ustawień — osobno dla każdego miejsca zapisu, bo listy się różnią.
    static var defaultShoppingList: String? {
        let key = taskDestination == .ticktick ? Key.tickTickShoppingList : Key.defaultShoppingList
        return UserDefaults.standard.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var taskDestination: TaskDestination {
        UserDefaults.standard.string(forKey: Key.taskDestination).flatMap(TaskDestination.init) ?? .apple
    }

    /// Magazyn dla nowych przypomnień, notatek i zakupów.
    static var taskStore: any TaskStore {
        switch taskDestination {
        case .apple: return RemindersService()
        case .ticktick: return TickTickService(token: KeychainStore.loadTickTickToken() ?? "")
        }
    }
}
