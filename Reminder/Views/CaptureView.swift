import SwiftUI
import SwiftData
import Combine

/// Logika przepływu: nasłuch → interpretacja LLM → (dopytanie) → karty → zapis / odliczanie.
/// UI faz renderuje `ContentView` inline (jeden ekran, jak w projekcie designu).
@MainActor
final class CaptureController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case processing
        case ask
        case result
        case failed(String)
    }

    /// Dopytanie o kontakt („Do której Ani wysłać?”).
    struct AskState: Equatable {
        var question: String
        var options: [ContactMatch]
        var actionID: UUID
    }

    struct Countdown: Equatable {
        var left: Double
        var total: Double
    }

    @Published var phase: Phase = .idle
    /// Na żywo z rozpoznawania mowy podczas nasłuchu.
    @Published var transcript: String = ""
    /// Polecenie, którego dotyczą karty.
    @Published var lastTranscript: String = ""
    @Published var silenceProgress: Double = 0
    @Published var actions: [PlannedAction] = []
    @Published var ask: AskState?
    @Published var countdown: Countdown?
    @Published var editingTranscript = false
    @Published var draft = ""
    /// Ostatni błąd dotyczy klucza API — ekran błędu pokazuje skrót do Ustawień.
    @Published var keyProblem = false
    @Published var choices = ChoiceSource()
    /// SMS czekający na arkusz Wiadomości.
    @Published var compose: MessageDraft?

    let speech = SpeechService()

    private var modelContext: ModelContext?
    private var cancellables: Set<AnyCancellable> = []
    private var countdownTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var composeContinuation: CheckedContinuation<Bool, Never>?
    private var isStarting = false

    init() {
        speech.$transcript.sink { [weak self] text in
            guard let self else { return }
            if self.phase == .listening { self.transcript = text }
        }.store(in: &cancellables)
        speech.$silenceProgress.assign(to: \.silenceProgress, on: self).store(in: &cancellables)
    }

    func attach(_ context: ModelContext) { modelContext = context }

    var isListening: Bool { phase == .listening }
    var isPreview: Bool { AppSettings.preview }
    var pending: [PlannedAction] { actions.filter { $0.status == .pending } }

    func micTapped() {
        switch phase {
        case .listening: speech.stop()
        case .idle, .failed: Task { await startListening() }
        case .result, .processing, .ask: break
        }
    }

    func startListening() async {
        guard !isStarting, phase != .listening, phase != .processing else { return }
        isStarting = true
        defer { isStarting = false }
        guard await SpeechService.requestPermissions() else {
            phase = .failed("Brak dostępu do mikrofonu lub rozpoznawania mowy — włącz w Ustawieniach.")
            return
        }
        // Nowe nagranie zamyka poprzednie karty (zapisane trafiają do historii).
        if phase == .result || phase == .ask { finishBatch() }
        transcript = ""
        phase = .listening
        speech.start { [weak self] transcript in
            Task { await self?.process(transcript) }
        }
    }

    func cancel() {
        speech.stop()
        phase = .idle
    }

    // MARK: - Interpretacja

    private func process(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = text
        guard !text.isEmpty else {
            // Cisza po automatycznym starcie nie jest błędem — wróć do ekranu startowego.
            phase = speech.errorMessage.map(Phase.failed) ?? .idle
            return
        }
        phase = .processing
        keyProblem = false
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            saveDraft(text)
            keyProblem = true
            phase = .failed("Brak klucza Claude API — dodaj go w Ustawieniach. Transkrypt zapisany jako draft.")
            return
        }
        do {
            let commands = try await CommandInterpreter(apiKey: apiKey).interpret(transcript: text)
            guard !commands.isEmpty else {
                phase = .failed("Nie rozpoznałem polecenia — spróbuj powiedzieć to inaczej.")
                return
            }
            await loadChoices()
            var prepared: [PlannedAction] = []
            for command in commands { prepared.append(await prepare(command)) }
            actions = prepared
            await askOrShowResult()
        } catch {
            saveDraft(text)
            if case InterpreterError.invalidAPIKey = error { keyProblem = true }
            phase = .failed("\(error.localizedDescription) Transkrypt zapisany jako draft.")
        }
    }

    private func loadChoices() async {
        async let lists = RemindersService().listNames()
        async let calendars = CalendarService().calendarNames()
        choices = ChoiceSource(reminderLists: await lists, calendars: await calendars)
    }

    /// Uzupełnia domyślne listy/kalendarz i wyszukuje kontakty.
    private func prepare(_ command: InterpretedCommand) async -> PlannedAction {
        var action = PlannedAction(command: Self.withDefaults(command))
        await resolveContacts(&action, allowAsk: true)
        return action
    }

    static func withDefaults(_ command: InterpretedCommand) -> InterpretedCommand {
        var c = command
        switch c.action {
        case .reminder:
            c.listName = c.listName ?? RemindersService().defaultListName() ?? "Przypomnienia"
        case .note:
            c.listName = c.listName ?? "Notatki"
        case .shopping:
            c.listName = c.listName ?? AppSettings.defaultShoppingList ?? RemindersService().shoppingListName() ?? "Zakupy"
        case .event:
            c.calendarName = c.calendarName ?? AppSettings.defaultCalendar ?? CalendarService().defaultCalendarName()
            if c.endDate == nil, let start = c.dueDateParsed { c.endDateParsed = start.addingTimeInterval(3600) }
        default:
            break
        }
        return c
    }

    private func resolveContacts(_ action: inout PlannedAction, allowAsk: Bool) async {
        guard [.message, .call].contains(action.command.action),
              let name = action.command.recipient, !name.isEmpty,
              let matches = try? await ContactsService().matches(for: name), !matches.isEmpty else { return }
        action.contacts = matches
        let exact = matches.first { $0.name.lowercased() == name.lowercased() }
        if let pick = exact ?? (matches.count == 1 || !allowAsk ? matches.first : nil) {
            action.command.recipient = pick.name
            action.command.phoneLabel = action.command.phoneLabel ?? pick.numbers.first?.label
            action.needsContactChoice = false
        } else {
            action.needsContactChoice = true
        }
    }

    private func askOrShowResult() async {
        if let next = actions.first(where: \.needsContactChoice) {
            let question = next.command.clarify
                ?? (next.command.action == .call ? "Do kogo zadzwonić?" : "Do kogo wysłać?")
            ask = AskState(question: question, options: next.contacts, actionID: next.id)
            phase = .ask
            return
        }
        ask = nil
        await showResult()
    }

    func pickContact(_ match: ContactMatch) {
        guard let ask, let index = actions.firstIndex(where: { $0.id == ask.actionID }) else { return }
        actions[index].command.recipient = match.name
        actions[index].command.phoneLabel = match.numbers.first?.label
        actions[index].needsContactChoice = false
        Task { await askOrShowResult() }
    }

    /// Bez podglądu bezpieczne akcje zapisują się od razu; SMS/połączenie czekają na odliczanie.
    private func showResult() async {
        phase = .result
        if !isPreview {
            for action in actions where action.command.action.isSafe && action.status == .pending {
                await run(action.id)
            }
        }
        startCountdown()
    }

    // MARK: - Wykonanie

    private func run(_ id: UUID) async {
        guard let modelContext, let index = actions.firstIndex(where: { $0.id == id }) else { return }
        let action = actions[index]
        actions[index].status = .running
        do {
            let result = try await ActionExecutor(modelContext: modelContext).execute(action.command, contact: action.contact)
            guard let i = actions.firstIndex(where: { $0.id == id }) else { return }
            actions[i].undo = result.undo
            if let message = result.message, action.command.action == .query {
                actions[i].command.notes = message
            }
            if let draft = result.compose {
                let sent = await presentCompose(draft)
                actions[i].status = sent ? .done : .undone
            } else {
                actions[i].status = .done
            }
        } catch {
            if let i = actions.firstIndex(where: { $0.id == id }) {
                actions[i].status = .failed(error.localizedDescription)
            }
        }
    }

    /// Arkusz Wiadomości w aplikacji; gdy niedostępny — otwiera systemową apkę.
    private func presentCompose(_ draft: MessageDraft) async -> Bool {
        guard MessageComposer.canSendText else {
            if let modelContext { await ActionExecutor(modelContext: modelContext).openMessages(draft) }
            return true
        }
        return await withCheckedContinuation { cont in
            composeContinuation = cont
            compose = draft
        }
    }

    func composeFinished(sent: Bool) {
        compose = nil
        composeContinuation?.resume(returning: sent)
        composeContinuation = nil
    }

    func startCountdown() {
        stopCountdown()
        guard phase == .result, !isPreview, let total = AppSettings.autoExecuteSeconds,
              pending.contains(where: { !$0.command.action.isSafe }) else { return }
        countdown = Countdown(left: total, total: total)
        let start = Date.now
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                let left = max(0, total - Date.now.timeIntervalSince(start))
                self?.countdown?.left = left
                if left <= 0 {
                    Task { await self?.executePending() }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    /// „Zapisz” / „Wyślij teraz” / koniec odliczania.
    func executePending() async {
        stopCountdown()
        for action in pending { await run(action.id) }
        scheduleFinish(after: 1.1)
    }

    func cancelAll() {
        stopCountdown()
        for i in actions.indices where actions[i].status == .pending { actions[i].status = .undone }
        scheduleFinish(after: 0.6)
    }

    /// „Odrzuć”: cofa wszystkie zapisane akcje i zamyka karty.
    func discardAll() {
        stopCountdown()
        for action in actions where action.status == .done && action.undo != nil { undo(action.id) }
        for i in actions.indices where actions[i].status == .pending { actions[i].status = .undone }
        scheduleFinish(after: 0.6)
    }

    var canDiscard: Bool { actions.contains { $0.status == .done && $0.undo != nil } }

    func undo(_ id: UUID) {
        guard let modelContext, let index = actions.firstIndex(where: { $0.id == id }),
              let token = actions[index].undo else { return }
        do {
            try ActionExecutor(modelContext: modelContext).undo(token)
            actions[index].status = .undone
            actions[index].undo = nil
        } catch {
            actions[index].status = .failed(error.localizedDescription)
        }
        if actions.allSatisfy({ $0.status == .undone }) { scheduleFinish(after: 0.6) }
    }

    private func scheduleFinish(after seconds: Double) {
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finishBatch()
        }
    }

    /// Zamyka karty: wykonane trafiają do historii „Ostatnio”.
    func finishBatch() {
        finishTask?.cancel()
        stopCountdown()
        if let modelContext {
            for action in actions where action.status == .done && action.command.action != .query {
                let kind = action.command.action
                modelContext.insert(Note(text: action.cardTitle, action: kind.rawValue,
                                         detail: action.historyDetail(label: kind.label)))
            }
        }
        actions = []
        ask = nil
        editingTranscript = false
        transcript = ""
        lastTranscript = ""
        phase = .idle
    }

    // MARK: - Edycja transkrypcji

    func beginEditTranscript() {
        finishTask?.cancel()
        stopCountdown()
        draft = lastTranscript
        editingTranscript = true
    }

    func cancelEditTranscript() {
        editingTranscript = false
        startCountdown()
    }

    /// „Analizuj ponownie”: cofa już zapisane akcje i interpretuje poprawiony tekst.
    func reanalyze() {
        editingTranscript = false
        if let modelContext {
            for action in actions where action.status == .done {
                if let token = action.undo { try? ActionExecutor(modelContext: modelContext).undo(token) }
            }
        }
        actions = []
        let text = draft
        Task { await process(text) }
    }

    // MARK: - Edycja pól (tryb podglądu)

    func setText(_ id: UUID, key: String, value: String) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[index].setText(key, value)
    }

    func setDate(_ id: UUID, date: Date?) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[index].setDate(date)
    }

    func setType(_ id: UUID, to type: CommandAction) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        var command = actions[index].command
        command.action = type
        // Lista/kalendarz zależą od typu — weź domyślne dla nowego.
        command.listName = nil
        command.calendarName = nil
        actions[index].command = Self.withDefaults(command)
    }

    private func saveDraft(_ transcript: String) {
        guard let modelContext else { return }
        ActionExecutor(modelContext: modelContext).saveDraft(transcript: transcript)
    }
}
