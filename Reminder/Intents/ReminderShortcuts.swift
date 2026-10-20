import AppIntents

/// Skrót Siri „Asystent” (Siri wymaga nazwy aplikacji w frazie).
/// Ten sam intent podepniesz pod Action Button / Back Tap w aplikacji Skróty.
struct ReminderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureReminderIntent(),
            phrases: [
                "Asystent \(.applicationName)",
                "Asystent w \(.applicationName)",
                "Nowe przypomnienie w \(.applicationName)",
            ],
            shortTitle: "Asystent",
            systemImageName: "mic.circle.fill"
        )
    }
}
