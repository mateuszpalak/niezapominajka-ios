import Foundation
import Synchronization

enum TickTickError: LocalizedError {
    case missingToken
    case invalidToken
    case locationUnsupported
    case notFound(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "Brak tokenu TickTick — wklej go w Ustawieniach."
        case .invalidToken: return "Token TickTick jest nieprawidłowy — wklej go ponownie w Ustawieniach."
        case .locationUnsupported:
            return "TickTick nie obsługuje przypomnień o miejscu — przełącz zapis na Przypomnienia Apple w Ustawieniach."
        case .notFound(let phrase): return "Nie znalazłem zadania pasującego do „\(phrase)”."
        case .badResponse(let status): return "TickTick odpowiedział błędem (HTTP \(status))."
        }
    }
}

/// Zapis do TickTick przez Open API z osobistym tokenem (TickTick → Ustawienia → Konto → API Token).
struct TickTickService: TaskStore {
    var token: String

    /// Nazwa skrzynki odbiorczej — `GET /project` jej nie zwraca, a API przyjmuje `projectId: "inbox"`.
    static let inboxName = "Skrzynka odbiorcza"
    private static let inboxID = "inbox"
    private static let baseURL = URL(string: "https://api.ticktick.com/open/v1/")!

    struct Project: Decodable, Sendable {
        let id: String
        let name: String
        var closed: Bool?
        var permission: String?
        var kind: String?

        var isWritable: Bool { closed != true && (permission ?? "write") == "write" }
    }

    private struct RemoteTask: Decodable {
        let id: String
        let projectId: String
        var title: String?
        var dueDate: String?
        var isAllDay: Bool?
    }

    /// Ostatnio pobrane listy — `defaultListName`/`shoppingListName` są synchroniczne.
    private static let projectCache = Mutex<[Project]>([])

    // MARK: - TaskStore

    func addTask(title: String, notes: String?, dueDate: Date?, listName: String?,
                 locationName: String?) async throws -> TaskRef {
        // Open API nie ma alarmów lokalizacyjnych — lepiej powiedzieć wprost niż zgubić miejsce.
        guard locationName == nil else { throw TickTickError.locationUnsupported }
        let projectID = try await projectID(named: listName)
        return try await create(Self.taskBody(title: title, notes: notes, dueDate: dueDate, projectID: projectID))
    }

    func addNote(title: String, notes: String?, listName: String) async throws -> TaskRef {
        let projectID = try await projectID(named: listName, kind: "NOTE")
        return try await create(Self.taskBody(title: title, notes: notes, dueDate: nil, projectID: projectID, kind: "NOTE"))
    }

    func addItems(_ items: [String], listName: String?) async throws -> [TaskRef] {
        let projectID = try await projectID(named: listName ?? shoppingListName() ?? "Zakupy")
        // Po kolei, żeby zachować kolejność z polecenia. `/task/batch` nie zwraca identyfikatorów do „Cofnij”.
        var refs: [TaskRef] = []
        for item in items {
            refs.append(try await create(Self.taskBody(title: item, notes: nil, dueDate: nil, projectID: projectID)))
        }
        return refs
    }

    func remove(_ refs: [TaskRef]) async throws {
        for case .ticktick(let project, let task) in refs {
            _ = try await send("DELETE", "project/\(project)/task/\(task)")
        }
    }

    func complete(matching phrase: String) async throws -> (ref: TaskRef, title: String) {
        // `/task/search` zwraca pustą listę nawet dla istniejących zadań — dopasowujemy lokalnie.
        let data = try await send("POST", "task/filter", body: ["status": [0]])
        let tasks = try JSONDecoder().decode([RemoteTask].self, from: data).map(Self.summary)
        guard let found = TaskMatcher.bestMatch(for: phrase, in: tasks),
              case .ticktick(let project, let task) = found.ref else {
            throw TickTickError.notFound(phrase)
        }
        _ = try await send("POST", "project/\(project)/task/\(task)/complete")
        return (found.ref, found.title)
    }

    func uncomplete(_ ref: TaskRef) async throws {
        guard case .ticktick(let project, let task) = ref else { return }
        // Aktualizacja częściowa: pozostałe pola zadania zostają bez zmian.
        _ = try await send("POST", "task/\(task)", body: ["id": task, "projectId": project, "status": 0])
    }

    func incompleteTasks(until end: Date) async throws -> [TaskSummary] {
        // `/task/undone` przyjmuje zakres do 14 dni — starsze zaległości nie trafią do podsumowania.
        let start = end.addingTimeInterval(-13 * 86_400)
        let data = try await send("POST", "task/undone", body: [
            "startDate": Self.formatDate(start), "endDate": Self.formatDate(end),
        ])
        return try JSONDecoder().decode([RemoteTask].self, from: data).map(Self.summary)
    }

    func listNames() async -> [String] {
        guard let projects = try? await fetchProjects() else { return [] }
        return [Self.inboxName] + projects.filter(\.isWritable).map(\.name).sorted()
    }

    func defaultListName() -> String? { Self.inboxName }

    func shoppingListName() -> String? {
        TaskMatcher.shoppingList(in: Self.projectCache.withLock { $0 }.filter(\.isWritable).map(\.name))
    }

    /// Sprawdza token lekkim zapytaniem o ustawienia konta.
    static func checkToken(_ token: String) async -> CommandInterpreter.KeyStatus {
        do {
            _ = try await TickTickService(token: token).send("POST", "preference")
            return .valid
        } catch TickTickError.invalidToken {
            return .invalid
        } catch {
            return .unreachable
        }
    }

    // MARK: - Listy

    private func fetchProjects() async throws -> [Project] {
        let projects = try JSONDecoder().decode([Project].self, from: try await send("GET", "project"))
        Self.projectCache.withLock { $0 = projects }
        return projects
    }

    /// Identyfikator listy o podanej nazwie; tworzy ją, jeśli nie istnieje. nil / skrzynka = skrzynka odbiorcza.
    private func projectID(named name: String?, kind: String = "TASK") async throws -> String {
        guard let name, !name.isEmpty, name != Self.inboxName else { return Self.inboxID }
        if let existing = try await fetchProjects().first(where: { $0.name == name && $0.isWritable }) {
            return existing.id
        }
        let data = try await send("POST", "project", body: ["name": name, "kind": kind, "viewMode": "list"])
        let created = try JSONDecoder().decode(Project.self, from: data)
        Self.projectCache.withLock { $0.append(created) }
        return created.id
    }

    // MARK: - Zadania

    private func create(_ body: [String: Any]) async throws -> TaskRef {
        let task = try JSONDecoder().decode(RemoteTask.self, from: try await send("POST", "task", body: body))
        // Odpowiedź podaje prawdziwy identyfikator skrzynki (np. „inbox116594728”) — potrzebny do usunięcia.
        return .ticktick(project: task.projectId, task: task.id)
    }

    /// Treść `POST /task`: termin z przypomnieniem w chwili terminu.
    static func taskBody(title: String, notes: String?, dueDate: Date?, projectID: String,
                         kind: String = "TEXT", timeZone: TimeZone = .current) -> [String: Any] {
        var body: [String: Any] = ["title": title, "projectId": projectID, "kind": kind]
        if let notes, !notes.isEmpty { body["content"] = notes }
        if let dueDate {
            let date = formatDate(dueDate, timeZone: timeZone)
            body["startDate"] = date
            body["dueDate"] = date
            body["timeZone"] = timeZone.identifier
            body["isAllDay"] = false
            body["reminders"] = ["TRIGGER:PT0S"]
        }
        return body
    }

    private static func summary(_ task: RemoteTask) -> TaskSummary {
        TaskSummary(ref: .ticktick(project: task.projectId, task: task.id), title: task.title ?? "",
                    dueDate: parseDate(task.dueDate), hasTime: task.isAllDay != true)
    }

    // MARK: - Daty („2026-10-25T15:00:00+0200”; odpowiedzi mają też milisekundy)

    static func formatDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter("yyyy-MM-dd'T'HH:mm:ssZ", timeZone: timeZone).string(from: date)
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return formatter("yyyy-MM-dd'T'HH:mm:ss.SSSZ").date(from: string)
            ?? formatter("yyyy-MM-dd'T'HH:mm:ssZ").date(from: string)
    }

    private static func formatter(_ format: String, timeZone: TimeZone = .current) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }

    // MARK: - HTTP

    private func send(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard !token.isEmpty else { throw TickTickError.missingToken }
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401, 403: throw TickTickError.invalidToken
        default: throw TickTickError.badResponse(status)
        }
    }
}
