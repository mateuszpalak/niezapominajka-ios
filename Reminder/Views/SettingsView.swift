import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = KeychainStore.loadAPIKey() ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Klucz Claude API")
                } footer: {
                    Text("Klucz jest przechowywany bezpiecznie w Keychain i używany do interpretacji poleceń głosowych. Wygenerujesz go na platform.claude.com.")
                }
            }
            .navigationTitle("Ustawienia")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") {
                        KeychainStore.saveAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
        }
    }
}
