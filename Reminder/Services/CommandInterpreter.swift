import Foundation

enum InterpreterError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case tooLong
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Brak klucza Claude API — ustaw go w ustawieniach."
        case .invalidAPIKey: return "Klucz API jest nieprawidłowy — wklej go ponownie w Ustawieniach."
        case .tooLong:
            return "Polecenie jest za długie (maks. \(CommandInterpreter.maxTranscriptLength) znaków) — podziel je na krótsze."
        case .badResponse(let detail): return "Błąd interpretacji: \(detail)"
        }
    }
}

/// Wysyła polski transkrypt do Claude API i dostaje listę strukturalnych poleceń.
struct CommandInterpreter {
    var apiKey: String

    // Stałe literały JSON Schema — nigdy niezmieniane, więc bezpieczne między wątkami.
    nonisolated(unsafe) private static let actionSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": ["type": "string", "enum": ["reminder", "note", "alarm", "shopping", "event", "message", "call", "query", "complete"]],
            "title": ["type": "string"],
            "dueDate": ["type": ["string", "null"], "description": "ISO 8601 z offsetem strefy, np. 2026-08-07T20:00:00+02:00; null gdy brak terminu"],
            "endDate": ["type": ["string", "null"], "description": "koniec wydarzenia (ISO 8601), tylko dla action=event; null = godzina po dueDate"],
            "notes": ["type": ["string", "null"]],
            "items": ["type": ["array", "null"], "items": ["type": "string"],
                      "description": "produkty na listę zakupów, tylko dla action=shopping"],
            "location": ["type": ["string", "null"],
                         "description": "miejsce: dla przypomnienia lokalizacyjnego (np. Lidl) albo miejsce wydarzenia (np. Biuro)"],
            "recipient": ["type": ["string", "null"],
                          "description": "imię/nazwa kontaktu w mianowniku dla action=message lub call, np. Mama, Ania"],
            "clarify": ["type": ["string", "null"],
                        "description": "dla message/call: pytanie, gdyby było kilka kontaktów o tym imieniu, np. Do której Ani wysłać?"],
            "confirmation": ["type": "string"],
        ],
        "required": ["action", "title", "dueDate", "endDate", "notes", "items", "location", "recipient", "clarify", "confirmation"],
        "additionalProperties": false,
    ]

    nonisolated(unsafe) private static let schema: [String: Any] = [
        "type": "object",
        "properties": ["actions": ["type": "array", "items": actionSchema]],
        "required": ["actions"],
        "additionalProperties": false,
    ]

    static func systemPrompt(now: Date = .now, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.timeZone = timeZone
        f.dateFormat = "EEEE, d MMMM yyyy, HH:mm"
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        return """
        Jesteś interpreterem polskich poleceń głosowych w aplikacji przypomnień. \
        Użytkownik mówi swobodnie po polsku. Twoim zadaniem jest zamienić transkrypt na listę akcji "actions". \
        Zwykle to jedna akcja, ale jeśli użytkownik w jednej wypowiedzi podał kilka poleceń \
        („dodaj do zakupów mleko i przypomnij mi o tabletce”), zwróć każde jako osobny element, w kolejności wypowiedzenia. \
        Rodzaje akcji:
        - "reminder": przypomnienie (z terminem, jeśli użytkownik go podał),
        - "alarm": tylko gdy użytkownik wyraźnie chce budzik/alarm ("obudź mnie", "ustaw alarm/budzik"),
        - "note": notatka bez terminu ("zanotuj", "zapisz", albo brak jakiegokolwiek odniesienia do czasu i charakter informacyjny),
        - "shopping": lista zakupów ("dodaj do zakupów / do listy zakupów", "kup", "muszę kupić") — \
        rozbij produkty na osobne pozycje w "items" (każda z wielkiej litery, np. ["Mleko", "Chleb"]), "title" ustaw na "Zakupy",
        - "event": wydarzenie w kalendarzu ("umów", "zaplanuj spotkanie", "wizyta", "dodaj do kalendarza") — "dueDate" to początek, \
        "endDate" koniec (null, gdy nie podano), "location" to miejsce (np. "Biuro"),
        - "message": użytkownik chce TERAZ wysłać wiadomość ("napisz do X, że…", "wyślij SMS do X") — \
        "recipient" to imię kontaktu w mianowniku (np. "do Ani" → "Ania"), "notes" to gotowa treść wiadomości \
        w pierwszej osobie (np. "Cześć, spóźnię się około 10 minut."), "clarify" to pytanie w stylu "Do której Ani wysłać?",
        - "call": użytkownik chce TERAZ zadzwonić ("zadzwoń do X") — "recipient" to imię kontaktu w mianowniku, \
        "clarify" np. "Do którego Marka zadzwonić?". \
        Uwaga: "przypomnij mi, żeby zadzwonić do X" to "reminder", nie "call"!
        - "query": użytkownik pyta o plany ("co mam dziś do zrobienia?", "jakie mam jutro plany?", "co mam w kalendarzu w piątek?") — \
        "dueDate" ustaw na południe pytanego dnia (null = dziś); "confirmation" krótkie, np. "Sprawdzam plany.",
        - "complete": użytkownik odhacza zadanie ("odhacz mleko", "zrobione: zadzwonić do mamy", "kupiłem chleb") — \
        "title" to fraza do dopasowania istniejącego przypomnienia (np. "mleko").
        Jeśli użytkownik wiąże przypomnienie z miejscem ("jak będę w Lidlu", "kiedy dojadę do pracy"), \
        ustaw "location" na nazwę miejsca, a action zostaw "reminder".
        Pola nieużywane przez dany rodzaj akcji ustaw na null.

        Teraz jest: \(f.string(from: now)) (\(iso.string(from: now))), strefa \(timeZone.identifier).
        Zasady dat: "wieczorem" ≈ 19:00, "rano" ≈ 8:00, "po południu" ≈ 15:00, o ile użytkownik nie podał godziny. \
        Jeśli podana godzina dziś już minęła, przyjmij jutro. "dueDate" zwróć w ISO 8601 z offsetem tej strefy, albo null.
        "title" to krótka treść zadania bez frazy czasowej i bez "przypomnij mi żeby" (np. "Zadzwonić do mamy").
        "confirmation" to jedno naturalne polskie zdanie potwierdzające, co zrobiłeś (np. "OK, przypomnę Ci o 20:00, żeby zadzwonić do mamy.").
        """
    }

    /// Limit tekstu wysyłanego do Claude — polecenia głosowe są krótkie, dłuższy tekst to raczej pomyłka albo nadużycie.
    static let maxTranscriptLength = 500

    func interpret(transcript: String) async throws -> [InterpretedCommand] {
        guard transcript.count <= Self.maxTranscriptLength else { throw InterpreterError.tooLong }
        return try await send(system: Self.systemPrompt(), user: transcript)
    }

    private func send(system: String, user: String) async throws -> [InterpretedCommand] {
        guard !apiKey.isEmpty else { throw InterpreterError.missingAPIKey }

        let body: [String: Any] = [
            "model": "claude-haiku-5-5",
            "max_tokens": 2048,
            "system": system,
            // Krótkie polecenia nie potrzebują myślenia — szybciej i taniej.
            "thinking": ["type": "disabled"],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": Self.schema]],
            "messages": [["role": "user", "content": user]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 401 { throw InterpreterError.invalidAPIKey }
            throw InterpreterError.badResponse(Self.errorMessage(from: data))
        }
        return try Self.parse(responseData: data)
    }

    /// Z odpowiedzi błędu API bierze samo `error.message` zamiast całego JSON-a.
    static func errorMessage(from data: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        return error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "błąd HTTP"
    }

    enum KeyStatus: Equatable { case valid, invalid, unreachable }

    /// Sprawdza klucz lekkim zapytaniem o listę modeli (bez zużycia tokenów).
    static func checkKey(_ key: String) async -> KeyStatus {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .unreachable }
        switch status {
        case 200: return .valid
        case 401, 403: return .invalid
        default: return .unreachable
        }
    }

    /// Przyjmuje `{"actions":[…]}`; dla zgodności także pojedynczy obiekt akcji.
    static func parse(responseData: Data) throws -> [InterpretedCommand] {
        let root = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if root?["stop_reason"] as? String == "refusal" {
            throw InterpreterError.badResponse("model odmówił wykonania polecenia")
        }
        guard let json = root,
              let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let textData = text.data(using: .utf8) else {
            throw InterpreterError.badResponse("nieoczekiwany format odpowiedzi")
        }
        struct Batch: Decodable { var actions: [InterpretedCommand] }
        if let batch = try? JSONDecoder().decode(Batch.self, from: textData) {
            return batch.actions
        }
        return [try JSONDecoder().decode(InterpretedCommand.self, from: textData)]
    }
}
