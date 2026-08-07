import Foundation
import SwiftUI
import AlarmKit

/// Prawdziwy alarm systemowy (AlarmKit, iOS 26) — dzwoni nawet w trybie cichym.
struct AlarmService {
    struct Metadata: AlarmMetadata {}

    func scheduleAlarm(title: String, date: Date) async throws {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .notDetermined:
            let state = try await manager.requestAuthorization()
            guard state == .authorized else { throw notAuthorized }
        case .denied:
            throw notAuthorized
        case .authorized:
            break
        @unknown default:
            break
        }

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(text: "Wyłącz", textColor: .white, systemImageName: "stop.circle")
        )
        let attributes = AlarmAttributes<Metadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: Color.orange
        )
        let configuration = AlarmManager.AlarmConfiguration(
            schedule: .fixed(date),
            attributes: attributes
        )
        _ = try await manager.schedule(id: UUID(), configuration: configuration)
    }

    private var notAuthorized: Error {
        NSError(domain: "Reminder", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Brak zgody na alarmy — włącz w Ustawieniach."])
    }
}
