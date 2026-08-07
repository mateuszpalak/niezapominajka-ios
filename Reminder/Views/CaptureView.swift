import SwiftUI
import SwiftData

/// Ekran nasłuchu: live transcript → interpretacja LLM → podgląd → wykonanie.
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @StateObject private var speech = SpeechService()

    enum Phase {
        case idle
        case listening
        case interpreting
        case preview(InterpretedCommand)
        case done(String)
        case failed(String, transcript: String?)
    }
    @State private var phase: Phase = .idle

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                content
                Spacer()
            }
            .padding()
            .navigationTitle("Słucham…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { speech.stop(); dismiss() }
                }
            }
            .task {
                // Przy starcie przez URL (kontrolka/Safari) scena bywa jeszcze
                // nieaktywna — mikrofon uruchomiony za wcześnie potrafi zawiesić
                // przejście między aplikacjami. Poczekaj na aktywację.
                var waited = 0
                while scenePhase != .active && waited < 20 {
                    try? await Task.sleep(for: .milliseconds(100))
                    waited += 1
                }
                await startListening()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            ProgressView()
        case .listening:
            VStack(spacing: 16) {
                Image(systemName: "waveform")
                    .font(.system(size: 56))
                    .symbolEffect(.variableColor.iterative, isActive: true)
                    .foregroundStyle(.tint)
                Text(speech.transcript.isEmpty ? "Mów teraz…" : speech.transcript)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Button("Gotowe") { speech.stop() }
                    .buttonStyle(.borderedProminent)
            }
        case .interpreting:
            VStack(spacing: 16) {
                ProgressView()
                Text("Rozumiem, co powiedziałeś…")
                Text("„\(speech.transcript)”")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case .preview(let command):
            previewCard(command)
        case .done(let confirmation):
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56)).foregroundStyle(.green)
                Text(confirmation).multilineTextAlignment(.center)
            }
        case .failed(let message, let transcript):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44)).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
                if transcript != nil {
                    Text("Transkrypt zapisany jako notatka-draft.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("Spróbuj ponownie") { Task { await startListening() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func previewCard(_ command: InterpretedCommand) -> some View {
        VStack(spacing: 16) {
            Label(actionLabel(command.action), systemImage: actionIcon(command.action))
                .font(.headline)
            Text(command.title).font(.title2).multilineTextAlignment(.center)
            if let items = command.items, !items.isEmpty {
                Text(items.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let date = command.dueDateParsed {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            if let location = command.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
            }
            if let recipient = command.recipient {
                Label(recipient, systemImage: "person")
                    .foregroundStyle(.secondary)
            }
            if let notes = command.notes, command.action == .message {
                Text("„\(notes)”").foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Anuluj") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Zapisz") { Task { await execute(command) } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func actionLabel(_ action: CommandAction) -> String {
        switch action {
        case .reminder: return "Przypomnienie"
        case .alarm: return "Alarm"
        case .note: return "Notatka"
        case .shopping: return "Lista zakupów"
        case .event: return "Wydarzenie w kalendarzu"
        case .message: return "Wiadomość"
        case .call: return "Telefon"
        case .query: return "Plany"
        case .complete: return "Odhacz"
        }
    }

    private func actionIcon(_ action: CommandAction) -> String {
        switch action {
        case .reminder: return "bell"
        case .alarm: return "alarm"
        case .note: return "note.text"
        case .shopping: return "cart"
        case .event: return "calendar"
        case .message: return "message"
        case .call: return "phone"
        case .query: return "list.bullet.rectangle"
        case .complete: return "checkmark.circle"
        }
    }

    private func startListening() async {
        guard await SpeechService.requestPermissions() else {
            phase = .failed("Brak dostępu do mikrofonu lub rozpoznawania mowy — włącz w Ustawieniach.", transcript: nil)
            return
        }
        phase = .listening
        speech.start { transcript in
            Task { await interpret(transcript) }
        }
    }

    private func interpret(_ transcript: String) async {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            let detail = speech.errorMessage ?? "Nic nie usłyszałem — spróbuj jeszcze raz."
            phase = .failed(detail, transcript: nil)
            return
        }
        phase = .interpreting
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            ActionExecutor(modelContext: modelContext).saveDraft(transcript: transcript)
            phase = .failed("Brak klucza Claude API — dodaj go w ustawieniach.", transcript: transcript)
            return
        }
        do {
            let command = try await CommandInterpreter(apiKey: apiKey).interpret(transcript: transcript)
            if command.action == .query {
                // Odczyt planów nie wymaga potwierdzania — wykonaj od razu.
                await execute(command)
            } else {
                phase = .preview(command)
            }
        } catch {
            ActionExecutor(modelContext: modelContext).saveDraft(transcript: transcript)
            phase = .failed(error.localizedDescription, transcript: transcript)
        }
    }

    private func execute(_ command: InterpretedCommand) async {
        do {
            let override = try await ActionExecutor(modelContext: modelContext).execute(command)
            let text = override ?? command.confirmation
            phase = .done(text)
            VoiceFeedback.shared.speak(text)
            // Dłuższe komunikaty (odczyt planów) zostają na ekranie dłużej.
            try? await Task.sleep(for: .seconds(min(12, max(3, Double(text.count) / 15))))
            dismiss()
        } catch {
            phase = .failed(error.localizedDescription, transcript: nil)
        }
    }
}
