import Foundation

enum InterpreterError: LocalizedError {
    case missingAPIKey
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Brak klucza Claude API — ustaw go w ustawieniach."
        case .badResponse(let detail): return "Błąd interpretacji: \(detail)"
        }
    }
}

/// Wysyła polski transkrypt do Claude API i dostaje strukturalną instrukcję.
struct CommandInterpreter {
    var apiKey: String

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": ["type": "string", "enum": ["reminder", "note", "alarm", "shopping", "event", "message", "call", "query", "complete"]],
            "title": ["type": "string"],
            "dueDate": ["type": ["string", "null"], "description": "ISO 8601 z offsetem strefy, np. 2026-08-07T20:00:00+02:00; null gdy brak terminu"],
            "notes": ["type": ["string", "null"]],
            "items": ["type": ["array", "null"], "items": ["type": "string"],
                      "description": "produkty na listę zakupów, tylko dla action=shopping"],
            "location": ["type": ["string", "null"],
                         "description": "nazwa miejsca dla przypomnienia lokalizacyjnego, np. Lidl"],
            "recipient": ["type": ["string", "null"],
                          "description": "imię/nazwa kontaktu dla action=message lub call, np. Mama"],
            "confirmation": ["type": "string"],
        ],
        "required": ["action", "title", "dueDate", "notes", "items", "location", "recipient", "confirmation"],
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
        Użytkownik mówi swobodnie po polsku. Twoim zadaniem jest zamienić transkrypt na jedną akcję:
        - "reminder": przypomnienie (z terminem, jeśli użytkownik go podał),
        - "alarm": tylko gdy użytkownik wyraźnie chce budzik/alarm ("obudź mnie", "ustaw alarm/budzik"),
        - "note": notatka bez terminu ("zanotuj", "zapisz", albo brak jakiegokolwiek odniesienia do czasu i charakter informacyjny),
        - "shopping": lista zakupów ("dodaj do zakupów / do listy zakupów", "kup", "muszę kupić") — \
        rozbij produkty na osobne pozycje w "items" (każda z wielkiej litery, np. ["Mleko", "Chleb"]), "title" ustaw na "Zakupy",
        - "event": wydarzenie w kalendarzu ("umów", "spotkanie", "wizyta", "dodaj do kalendarza") — "dueDate" to początek,
        - "message": użytkownik chce TERAZ wysłać wiadomość ("napisz do X, że…", "wyślij wiadomość do X") — \
        "recipient" to imię kontaktu tak jak wypowiedziane (np. "Mama"), "notes" to treść wiadomości do wysłania,
        - "call": użytkownik chce TERAZ zadzwonić ("zadzwoń do X") — "recipient" to imię kontaktu. \
        Uwaga: "przypomnij mi, żeby zadzwonić do X" to "reminder", nie "call"!
        - "query": użytkownik pyta o plany ("co mam dziś do zrobienia?", "jakie mam jutro plany?", "co mam w kalendarzu w piątek?") — \
        "dueDate" ustaw na południe pytanego dnia (null = dziś); "confirmation" krótkie, np. "Sprawdzam plany.",
        - "complete": użytkownik odhacza zadanie ("odhacz mleko", "zrobione: zadzwonić do mamy", "kupiłem chleb") — \
        "title" to fraza do dopasowania istniejącego przypomnienia (np. "mleko").
        Jeśli użytkownik wiąże przypomnienie z miejscem ("jak będę w Lidlu", "kiedy dojadę do pracy"), \
        ustaw "location" na nazwę miejsca, a action zostaw "reminder".

        Teraz jest: \(f.string(from: now)) (\(iso.string(from: now))), strefa \(timeZone.identifier).
        Zasady dat: "wieczorem" ≈ 19:00, "rano" ≈ 8:00, "po południu" ≈ 15:00, o ile użytkownik nie podał godziny. \
        Jeśli podana godzina dziś już minęła, przyjmij jutro. "dueDate" zwróć w ISO 8601 z offsetem tej strefy, albo null.
        "title" to krótka treść zadania bez frazy czasowej i bez "przypomnij mi żeby" (np. "Zadzwonić do mamy").
        "confirmation" to jedno naturalne polskie zdanie potwierdzające, co zrobiłeś (np. "OK, przypomnę Ci o 20:00, żeby zadzwonić do mamy.").
        """
    }

    func interpret(transcript: String) async throws -> InterpretedCommand {
        guard !apiKey.isEmpty else { throw InterpreterError.missingAPIKey }

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1024,
            "system": Self.systemPrompt(),
            "output_config": ["format": ["type": "json_schema", "schema": Self.schema]],
            "messages": [["role": "user", "content": transcript]],
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
            let detail = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw InterpreterError.badResponse(detail)
        }
        return try Self.parse(responseData: data)
    }

    static func parse(responseData: Data) throws -> InterpretedCommand {
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let textData = text.data(using: .utf8) else {
            throw InterpreterError.badResponse("nieoczekiwany format odpowiedzi")
        }
        return try JSONDecoder().decode(InterpretedCommand.self, from: textData)
    }
}
