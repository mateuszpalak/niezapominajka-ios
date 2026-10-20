import AppIntents

/// App Intent „Asystent” — otwiera aplikację od razu w trybie nasłuchu.
/// Współdzielony z rozszerzeniem widżetów (kontrolka na ekranie blokady / Action Button).
struct CaptureReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Asystent"
    static let description = IntentDescription("Otwiera aplikację od razu w trybie słuchania i wykonuje Twoje polecenie głosowe.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        AppState.shared.startCaptureRequested = true
        #endif
        return .result()
    }
}
