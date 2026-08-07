import SwiftUI
import SwiftData

@main
struct ReminderApp: App {
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .modelContainer(for: Note.self)
    }
}

/// Globalny stan aplikacji — App Intent ustawia `startCaptureRequested`,
/// żeby UI od razu wszedł w tryb nasłuchu.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var startCaptureRequested = false
}
