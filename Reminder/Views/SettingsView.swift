import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = KeychainStore.loadAPIKey() ?? ""
    @AppStorage(AppSettings.Key.listenOnOpen) private var listenOnOpen = true
    @AppStorage(AppSettings.Key.preview) private var preview = false
    @AppStorage(AppSettings.Key.autoExecute) private var autoExecute = "3"
    @AppStorage(AppSettings.Key.defaultCalendar) private var defaultCalendar = ""
    @AppStorage(AppSettings.Key.defaultShoppingList) private var defaultShoppingList = ""
    @State private var calendars: [String] = []
    @State private var lists: [String] = []
    @State private var systemCalendar = ""
    @State private var detectedShoppingList = "Zakupy"

    private var hasKey: Bool { apiKey.trimmingCharacters(in: .whitespacesAndNewlines).count > 8 }

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
                    HStack {
                        Text("Stan")
                        Spacer()
                        Circle()
                            .fill(hasKey ? Color(hex: 0x34C759) : Color(.systemGray4))
                            .frame(width: 8, height: 8)
                        Text(hasKey ? "Klucz zapisany" : "Brak klucza")
                            .foregroundStyle(.secondary)
                    }
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

                Section("Domyślne") {
                    Picker("Kalendarz", selection: Binding(
                        get: { defaultCalendar.isEmpty ? systemCalendar : defaultCalendar },
                        set: { defaultCalendar = $0 })) {
                        ForEach(options(calendars, current: defaultCalendar.isEmpty ? systemCalendar : defaultCalendar),
                                id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Lista zakupów", selection: Binding(
                        get: { defaultShoppingList.isEmpty ? detectedShoppingList : defaultShoppingList },
                        set: { defaultShoppingList = $0 })) {
                        ForEach(options(lists, current: defaultShoppingList.isEmpty ? detectedShoppingList : defaultShoppingList),
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
            .task { await loadDefaults() }
            .onDisappear {
                KeychainStore.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func options(_ names: [String], current: String) -> [String] {
        names.contains(current) || current.isEmpty ? names : [current] + names
    }

    private func loadDefaults() async {
        calendars = await CalendarService().calendarNames()
        lists = await RemindersService().listNames()
        systemCalendar = CalendarService().defaultCalendarName() ?? calendars.first ?? ""
        detectedShoppingList = RemindersService().shoppingListName() ?? "Zakupy"
    }
}
