import AppIntents

/// App Intent do podpięcia pod Back Tap / Action Button (przez aplikację Skróty).
/// Otwiera aplikację od razu w trybie nasłuchu.
struct CaptureReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Nowe przypomnienie głosowe"
    static var description = IntentDescription("Uruchamia nasłuch i tworzy przypomnienie z Twojego polecenia głosowego.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.startCaptureRequested = true
        return .result()
    }
}

struct ReminderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureReminderIntent(),
            phrases: ["Nowe przypomnienie w \(.applicationName)"],
            shortTitle: "Przypomnienie głosowe",
            systemImageName: "mic.circle.fill"
        )
    }
}
