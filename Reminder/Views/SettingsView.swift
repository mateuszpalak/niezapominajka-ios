import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = KeychainStore.loadAPIKey() ?? ""
    @AppStorage(AppSettings.Key.listenOnOpen) private var listenOnOpen = true
    @AppStorage(AppSettings.Key.preview) private var preview = false
    @AppStorage(AppSettings.Key.autoExecute) private var autoExecute = "3"
    @AppStorage(AppSettings.Key.defaultCalendar) private var defaultCalendar = ""
    @AppStorage(AppSettings.Key.defaultShoppingList) private var defaultShoppingList = ""
    @AppStorage(AppSettings.Key.tickTickShoppingList) private var tickTickShoppingList = ""
    @AppStorage(AppSettings.Key.taskDestination) private var taskDestination = TaskDestination.apple
    @State private var tickTickToken: String = KeychainStore.loadTickTickToken() ?? ""
    @State private var tokenStatus: CommandInterpreter.KeyStatus?
    @State private var checkingToken = false
    @State private var calendars: [String] = []
    @State private var lists: [String] = []
    @State private var systemCalendar = ""
    @State private var detectedShoppingList = "Zakupy"

    @State private var keyStatus: CommandInterpreter.KeyStatus?
    @State private var checkingKey = false

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedToken: String { tickTickToken.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Zadania idą do TickTick — listy i token bierzemy stamtąd.
    private var usesTickTick: Bool { taskDestination == .ticktick }

    /// Wiersz „Stan” z kropką, wspólny dla klucza Claude i tokenu TickTick.
    private func statusRow(_ status: CommandInterpreter.KeyStatus?, checking: Bool, isEmpty: Bool,
                           noun: (missing: String, valid: String, invalid: String)) -> some View {
        let text: String
        let color: Color
        if isEmpty {
            (text, color) = (noun.missing, Color(.systemGray4))
        } else if checking {
            (text, color) = ("Sprawdzam…", Color(.systemGray4))
        } else {
            switch status {
            case .valid: (text, color) = (noun.valid, Color(hex: 0x34C759))
            case .invalid: (text, color) = (noun.invalid, Color(hex: 0xFF3B30))
            case .unreachable: (text, color) = ("Nie można sprawdzić", Color(hex: 0xFF9500))
            case nil: (text, color) = ("Sprawdzam…", Color(.systemGray4))
            }
        }
        return HStack {
            Text("Stan")
            Spacer()
            if checking {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Text("Klucz API")
                        SecureField("sk-ant-…", text: $apiKey)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    statusRow(keyStatus, checking: checkingKey, isEmpty: trimmedKey.isEmpty,
                              noun: ("Brak klucza", "Klucz działa", "Nieprawidłowy klucz"))
                    // Sprawdź klucz chwilę po wpisaniu/wklejeniu.
                    .task(id: trimmedKey) { await verifyKey() }
                } header: {
                    Text("Claude API")
                } footer: {
                    Text("Klucz jest przechowywany wyłącznie na tym urządzeniu i służy do rozpoznawania poleceń głosowych.")
                }

                Section {
                    Toggle("Słuchaj po otwarciu", isOn: $listenOnOpen)
                    Toggle("Podgląd przed wykonaniem", isOn: $preview)
                    HStack(spacing: 12) {
                        Text("Wykonaj po")
                            .lineLimit(1)
                        Spacer()
                        Picker("Wykonaj po", selection: $autoExecute) {
                            Text("Wył.").tag("off")
                            Text("3 s").tag("3")
                            Text("5 s").tag("5")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }
                    .disabled(preview)
                    .opacity(preview ? 0.4 : 1)
                } header: {
                    Text("Działanie")
                } footer: {
                    Text(preview
                         ? "Każde polecenie czeka na Twoje zatwierdzenie. Pola możesz edytować przed zapisaniem."
                         : "Notatki, przypomnienia, wydarzenia i zakupy zapisują się od razu i można je cofnąć. SMS i połączenie wykonują się po odliczaniu.")
                }

                Section {
                    Picker("Zapisuj w", selection: $taskDestination) {
                        ForEach(TaskDestination.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if usesTickTick {
                        HStack(spacing: 12) {
                            Text("Token")
                            SecureField("tp_…", text: $tickTickToken)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        statusRow(tokenStatus, checking: checkingToken, isEmpty: trimmedToken.isEmpty,
                                  noun: ("Brak tokenu", "Token działa", "Nieprawidłowy token"))
                            .task(id: trimmedToken) { await verifyToken() }
                    }
                } header: {
                    Text("Zadania")
                } footer: {
                    Text(usesTickTick
                         ? "Token utworzysz w TickTick w przeglądarce: awatar → Ustawienia → Konto → API Token. Wydarzenia nadal trafiają do Kalendarza Apple."
                         : "Przypomnienia, notatki i zakupy trafiają do aplikacji Przypomnienia.")
                }

                Section("Domyślne") {
                    Picker("Kalendarz", selection: Binding(
                        get: { defaultCalendar.isEmpty ? systemCalendar : defaultCalendar },
                        set: { defaultCalendar = $0 })) {
                        ForEach(options(calendars, current: defaultCalendar.isEmpty ? systemCalendar : defaultCalendar),
                                id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Lista zakupów", selection: Binding(
                        get: { shoppingList.isEmpty ? detectedShoppingList : shoppingList },
                        set: { shoppingList = $0 })) {
                        ForEach(options(lists, current: shoppingList.isEmpty ? detectedShoppingList : shoppingList),
                                id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .navigationTitle("Ustawienia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
            // Listy zależą od miejsca zapisu — wczytaj ponownie po zmianie albo po sprawdzeniu tokenu.
            .task(id: "\(taskDestination.rawValue)|\(tokenStatus == .valid)") { await loadDefaults() }
            .onDisappear {
                KeychainStore.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                KeychainStore.saveTickTickToken(trimmedToken)
            }
        }
    }

    private func verifyKey() async {
        let key = trimmedKey
        guard !key.isEmpty else { keyStatus = nil; return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        checkingKey = true
        defer { checkingKey = false }
        let status = await CommandInterpreter.checkKey(key)
        guard !Task.isCancelled else { return }
        keyStatus = status
    }

    private func verifyToken() async {
        let token = trimmedToken
        guard !token.isEmpty else { tokenStatus = nil; return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        checkingToken = true
        defer { checkingToken = false }
        let status = await TickTickService.checkToken(token)
        guard !Task.isCancelled else { return }
        tokenStatus = status
    }

    /// Wybrana lista zakupów — osobno dla Przypomnień Apple i TickTick.
    private var shoppingList: String {
        get { usesTickTick ? tickTickShoppingList : defaultShoppingList }
        nonmutating set {
            if usesTickTick { tickTickShoppingList = newValue } else { defaultShoppingList = newValue }
        }
    }

    private func options(_ names: [String], current: String) -> [String] {
        names.contains(current) || current.isEmpty ? names : [current] + names
    }

    private func loadDefaults() async {
        calendars = await CalendarService().calendarNames()
        let tasks: any TaskStore = usesTickTick ? TickTickService(token: trimmedToken) : RemindersService()
        lists = await tasks.listNames()
        systemCalendar = CalendarService().defaultCalendarName() ?? calendars.first ?? ""
        detectedShoppingList = tasks.shoppingListName() ?? "Zakupy"
    }
}
