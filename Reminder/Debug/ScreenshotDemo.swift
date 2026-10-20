#if DEBUG
import Foundation
import SwiftData

/// Stany do zrzutów ekranu w README: `-demo home|listening|result|multi|sms|settings`.
/// Tylko w buildzie Debug — nic nie zapisuje do Przypomnień ani Kalendarza.
enum ScreenshotDemo {
    static var scene: String? { UserDefaults.standard.string(forKey: "demo") }

    /// Ustawia kontroler w danym stanie. Zwraca true, gdy tryb demo jest aktywny.
    @MainActor
    static func apply(to capture: CaptureController, context: ModelContext, openSettings: () -> Void) -> Bool {
        guard let scene else { return false }
        seedHistory(context)
        switch scene {
        case "listening":
            capture.phase = .listening
            capture.transcript = "Przypomnij mi jutro o piętnastej, żeby odebrać leki"
            capture.silenceProgress = 0.55
        case "result":
            capture.lastTranscript = "Przypomnij mi jutro o piętnastej, żeby odebrać leki z apteki"
            capture.actions = [done(InterpretedCommand(
                action: .reminder, title: "Odebrać leki z apteki", dueDate: iso(day: 1, hour: 15),
                confirmation: "", listName: "Przypomnienia"))]
            capture.phase = .result
        case "multi":
            capture.lastTranscript = "Dodaj do zakupów mleko i masło, i przypomnij mi o dwudziestej o tabletce"
            capture.actions = [
                done(InterpretedCommand(action: .shopping, title: "Zakupy", items: ["Mleko", "Masło"],
                                        confirmation: "", listName: "Zakupy")),
                done(InterpretedCommand(action: .reminder, title: "Wziąć tabletkę", dueDate: iso(day: 0, hour: 20),
                                        confirmation: "", listName: "Przypomnienia")),
            ]
            capture.phase = .result
        case "sms":
            capture.lastTranscript = "Wyślij SMS do Ani, że spóźnię się dziesięć minut"
            capture.actions = [PlannedAction(command: InterpretedCommand(
                action: .message, title: "SMS do Ani", notes: "Cześć, spóźnię się około 10 minut.",
                recipient: "Ania Kowalska", confirmation: ""))]
            capture.countdown = .init(left: 2.2, total: 3)
            capture.phase = .result
        case "settings":
            openSettings()
        default:
            break
        }
        return true
    }

    private static func done(_ command: InterpretedCommand) -> PlannedAction {
        var action = PlannedAction(command: command)
        action.status = .done
        action.undo = .reminders(["demo"])
        return action
    }

    private static func iso(day: Int, hour: Int) -> String {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: day, to: .now) ?? .now
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
        return ISO8601DateFormatter().string(from: date)
    }

    private static func seedHistory(_ context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<Note>())) == 0 else { return }
        let samples: [(String, CommandAction, String, TimeInterval)] = [
            ("Spotkanie z Markiem", .event, "Wydarzenie · Piątek, 12:00–13:00", -3_600),
            ("Mleko, masło, chleb", .shopping, "Lista zakupów · Zakupy", -7_200),
            ("Prezent dla taty: zestaw do kawy", .note, "Notatka · Notatki", -86_400),
        ]
        for (text, action, detail, offset) in samples {
            context.insert(Note(text: text, createdAt: .now.addingTimeInterval(offset),
                                action: action.rawValue, detail: detail))
        }
    }
}
#endif
