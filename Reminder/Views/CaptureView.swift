import SwiftUI
import SwiftData

/// Logika przepływu: nasłuch → interpretacja LLM → podgląd → wykonanie.
/// UI faz renderuje `ContentView` inline (jeden ekran, jak w projekcie designu).
@MainActor
final class CaptureController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case interpreting
        case preview(InterpretedCommand)
        case done(String)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var transcript: String = ""
    @Published var lastTranscript: String = ""
    let speech = SpeechService()

    private var modelContext: ModelContext?
    private var cancellable: Any?

    init() {
        cancellable = speech.$transcript.assign(to: \.transcript, on: self)
    }

    func attach(_ context: ModelContext) { modelContext = context }

    var isListening: Bool { phase == .listening }

    func micTapped() {
        switch phase {
        case .listening: speech.stop()
        case .idle, .done, .failed: Task { await startListening() }
        default: break
        }
    }

    func startListening() async {
        guard await SpeechService.requestPermissions() else {
            phase = .failed("Brak dostępu do mikrofonu lub rozpoznawania mowy — włącz w Ustawieniach.")
            return
        }
        transcript = ""
        phase = .listening
        speech.start { [weak self] transcript in
            Task { await self?.interpret(transcript) }
        }
    }

    func cancel() {
        speech.stop()
        phase = .idle
    }

    private func interpret(_ transcript: String) async {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = transcript
        guard !transcript.isEmpty else {
            phase = .failed(speech.errorMessage ?? "Nic nie usłyszałem — spróbuj jeszcze raz.")
            return
        }
        phase = .interpreting
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            saveDraft(transcript)
            phase = .failed("Brak klucza Claude API — dodaj go w ustawieniach. Transkrypt zapisany jako draft.")
            return
        }
        do {
            let command = try await CommandInterpreter(apiKey: apiKey).interpret(transcript: transcript)
            if command.action == .query {
                await execute(command)   // odczyt planów nie wymaga potwierdzania
            } else {
                phase = .preview(command)
            }
        } catch {
            saveDraft(transcript)
            phase = .failed("\(error.localizedDescription) Transkrypt zapisany jako draft.")
        }
    }

    func execute(_ command: InterpretedCommand) async {
        guard let modelContext else { return }
        do {
            let override = try await ActionExecutor(modelContext: modelContext).execute(command)
            let text = override ?? command.confirmation
            if command.action != .query {
                modelContext.insert(Note(text: command.title, action: command.action.rawValue))
            }
            phase = .done(text)
            VoiceFeedback.shared.speak(text)
            try? await Task.sleep(for: .seconds(min(12, max(3, Double(text.count) / 15))))
            if case .done = phase { phase = .idle }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func saveDraft(_ transcript: String) {
        guard let modelContext else { return }
        ActionExecutor(modelContext: modelContext).saveDraft(transcript: transcript)
    }
}

// MARK: - Prezentacja akcji (ikona, kolor, nazwa) — wg designu

extension CommandAction {
    var label: String {
        switch self {
        case .reminder: return "Przypomnienie"
        case .alarm: return "Alarm"
        case .note: return "Notatka"
        case .shopping: return "Lista zakupów"
        case .event: return "Wydarzenie"
        case .message: return "Wiadomość SMS"
        case .call: return "Połączenie"
        case .query: return "Plany"
        case .complete: return "Odhaczone"
        }
    }

    var symbol: String {
        switch self {
        case .reminder: return "bell.fill"
        case .alarm: return "alarm.fill"
        case .note: return "note.text"
        case .shopping: return "cart.fill"
        case .event: return "calendar"
        case .message: return "message.fill"
        case .call: return "phone.fill"
        case .query: return "list.bullet.rectangle"
        case .complete: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .reminder, .alarm: return .orange
        case .shopping, .call, .complete: return .green
        case .message, .query: return .blue
        case .event: return .red
        case .note: return .gray
        }
    }
}

extension InterpretedCommand {
    /// Jednolinijkowy opis szczegółów pod tytułem karty wyniku.
    var detailLine: String {
        var parts: [String] = []
        if let items, !items.isEmpty { parts.append(items.joined(separator: " · ")) }
        if let date = dueDateParsed { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        if let location { parts.append(location) }
        if let recipient { parts.append(recipient) }
        if let notes, action == .message { parts.append("„\(notes)”") }
        return parts.joined(separator: " · ")
    }
}
