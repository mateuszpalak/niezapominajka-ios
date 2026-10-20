import Foundation
import AVFoundation
import Speech

/// Nasłuch mikrofonu + rozpoznawanie polskiej mowy (SFSpeechRecognizer, pl-PL).
/// Auto-stop po 2,5 s ciszy od ostatniego fragmentu transkryptu (postęp ciszy w `silenceProgress`),
/// po `maxDuration` nagrywania albo gdy tekst dojdzie do limitu interpretera.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening = false
    @Published var errorMessage: String?
    /// 0…1 — jak długo trwa cisza po ostatnim słowie; 1 = koniec nagrania.
    @Published var silenceProgress: Double = 0

    static let silenceTimeout: TimeInterval = 2.5
    /// Górny limit jednego nagrania — chroni przed wysłaniem do Claude bardzo długiego tekstu.
    static let maxDuration: TimeInterval = 60

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pl-PL"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastHeard = Date()
    private var startedAt = Date()
    private var onFinish: ((String) -> Void)?

    /// `nonisolated`: callback zgody przychodzi na wątku w tle — w trybie Swift 6
    /// domknięcie odziedziczyłoby @MainActor i wywróciło aplikację przy sprawdzeniu izolacji.
    nonisolated static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        return speech && mic
    }

    func start(onFinish: @escaping (String) -> Void) {
        guard !isListening else { return }
        self.onFinish = onFinish
        transcript = ""
        errorMessage = nil
        guard let recognizer else {
            errorMessage = "System nie obsługuje rozpoznawania polskiej mowy (locale pl-PL)."
            finish()
            return
        }
        // Dostępność bywa zgłaszana z opóźnieniem tuż po utworzeniu recognizera —
        // poczekaj do ~3 s zanim uznamy, że naprawdę nie działa.
        Task { @MainActor in
            var attempts = 0
            while !recognizer.isAvailable && attempts < 15 {
                try? await Task.sleep(for: .milliseconds(200))
                attempts += 1
            }
            guard self.onFinish != nil else { return }  // użytkownik zamknął ekran
            guard recognizer.isAvailable else {
                self.errorMessage = """
                Rozpoznawanie mowy jest teraz niedostępne. Sprawdź: \
                Ustawienia → Główne → Klawiatura → włącz „Dyktowanie” (z językiem polskim) \
                oraz połączenie z internetem. Uwaga: mikrofon i dyktowanie nie działają w symulatorze — testuj na iPhonie.
                """
                self.finish()
                return
            }
            self.beginRecognition(recognizer)
        }
    }

    private func beginRecognition(_ recognizer: SFSpeechRecognizer) {

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Nie wymuszamy on-device: bez pobranego polskiego modelu transkrypcja
            // zwracałaby pusty wynik. System sam wybierze lokalne, gdy dostępne.
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(appendingTo: request))
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            startedAt = .now
            resetSilenceTimer()

            task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, isFinal, failed in
                Task { @MainActor in
                    guard let self else { return }
                    if let text {
                        let limit = CommandInterpreter.maxTranscriptLength
                        guard text.count < limit else {
                            self.transcript = Self.truncated(text, to: limit)
                            self.finish()
                            return
                        }
                        self.transcript = text
                        self.resetSilenceTimer()
                        if isFinal { self.finish() }
                    }
                    if failed, self.isListening { self.finish() }
                }
            })
        } catch {
            errorMessage = "Nie udało się uruchomić mikrofonu: \(error.localizedDescription)"
            isListening = false
            stopAudio()
            finish()
        }
    }

    // Domknięcia wołane przez system na wątkach audio / rozpoznawania mowy budujemy poza
    // @MainActor, żeby nie dziedziczyły izolacji (Swift 6 sprawdza ją w trakcie działania).

    private nonisolated static func tapBlock(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    /// Przekazuje dalej tylko wartości Sendable: tekst, czy wynik końcowy, czy wystąpił błąd.
    private nonisolated static func resultHandler(
        _ handle: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            handle(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    /// Ręczne zakończenie nasłuchu (tap użytkownika).
    func stop() { finish() }

    private func resetSilenceTimer() {
        lastHeard = .now
        silenceProgress = 0
        guard silenceTimer == nil else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickSilence() }
        }
    }

    /// Cisza liczy się dopiero, gdy coś już usłyszeliśmy.
    private func tickSilence() {
        if isListening, Date.now.timeIntervalSince(startedAt) >= Self.maxDuration { finish(); return }
        guard isListening, !transcript.isEmpty else { silenceProgress = 0; return }
        let progress = min(1, Date.now.timeIntervalSince(lastHeard) / Self.silenceTimeout)
        silenceProgress = progress
        if progress >= 1 { finish() }
    }

    /// Ucina tekst do limitu na granicy słowa.
    static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        guard let space = head.lastIndex(of: " ") else { return String(head) }
        return String(head[..<space])
    }

    private func finish() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        silenceProgress = 0
        if isListening {
            isListening = false
            stopAudio()
        }
        // Callback odpala się zawsze (nawet po nieudanym starcie), żeby UI
        // nigdy nie utknęło na ekranie nasłuchu.
        guard let callback = onFinish else { return }
        onFinish = nil
        callback(transcript)
    }

    private func stopAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        // Deaktywacja sesji audio bywa wolna (~100–200 ms) — nie rób jej na main.
        Task.detached {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
