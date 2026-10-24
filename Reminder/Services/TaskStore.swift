import Foundation

/// Gdzie zapisują się przypomnienia, notatki i zakupy (Ustawienia → Zadania).
enum TaskDestination: String, CaseIterable {
    case apple
    case ticktick

    var label: String {
        switch self {
        case .apple: return "Przypomnienia Apple"
        case .ticktick: return "TickTick"
        }
    }
}

/// Identyfikator zapisanego zadania — razem z miejscem, w którym leży (do „Cofnij”).
enum TaskRef: Equatable, Sendable {
    case apple(String)
    case ticktick(project: String, task: String)

    /// Magazyn, w którym zapisano zadanie — „Cofnij” działa także po zmianie ustawienia.
    var store: any TaskStore {
        switch self {
        case .apple: return RemindersService()
        case .ticktick: return TickTickService(token: KeychainStore.loadTickTickToken() ?? "")
        }
    }
}

/// Niewykonane zadanie do podsumowania dnia i odhaczania.
struct TaskSummary: Sendable {
    let ref: TaskRef
    let title: String
    let dueDate: Date?
    /// false = zadanie na cały dzień (bez godziny).
    let hasTime: Bool
}

/// Wspólny interfejs Przypomnień Apple i TickTick.
protocol TaskStore: Sendable {
    /// Zadanie z terminem (opcjonalnie) na podanej liście albo domyślnej.
    func addTask(title: String, notes: String?, dueDate: Date?, listName: String?,
                 locationName: String?) async throws -> TaskRef
    /// Notatka bez terminu.
    func addNote(title: String, notes: String?, listName: String) async throws -> TaskRef
    /// Produkty na listę zakupów: podaną albo wykrytą.
    func addItems(_ items: [String], listName: String?) async throws -> [TaskRef]
    /// Usuwa zapisane wcześniej zadania („Cofnij”); pomija cudze identyfikatory.
    func remove(_ refs: [TaskRef]) async throws
    /// Odhacza pierwsze niewykonane zadanie pasujące do frazy.
    func complete(matching phrase: String) async throws -> (ref: TaskRef, title: String)
    /// Cofa odhaczenie.
    func uncomplete(_ ref: TaskRef) async throws
    /// Niewykonane zadania z terminem do podanej chwili.
    func incompleteTasks(until end: Date) async throws -> [TaskSummary]
    /// Nazwy list (do wyboru na karcie i w Ustawieniach).
    func listNames() async -> [String]
    /// Nazwa listy, na którą trafia zadanie bez wskazanej listy.
    func defaultListName() -> String?
    /// Wykryta lista zakupów („zakupy”/„shopping”).
    func shoppingListName() -> String?
}

enum TaskMatcher {
    /// Pierwsze zadanie pasujące do frazy: zawieranie w obie strony albo wspólne słowo.
    static func bestMatch(for phrase: String, in tasks: [TaskSummary]) -> TaskSummary? {
        let needle = phrase.lowercased()
        return tasks.first {
            let title = $0.title.lowercased()
            return title.contains(needle) || needle.contains(title)
                || !Set(title.split(separator: " ")).isDisjoint(with: needle.split(separator: " "))
        }
    }

    /// Lista zakupów wśród nazw list.
    static func shoppingList(in names: [String]) -> String? {
        names.first {
            let t = $0.lowercased()
            return t.contains("zakup") || t.contains("shopping")
        }
    }
}
