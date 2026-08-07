import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Environment(\.modelContext) private var modelContext
    @State private var showCapture = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showCapture = true
                    } label: {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "mic.circle.fill")
                                    .font(.system(size: 64))
                                Text("Powiedz, co mam zapamiętać")
                                    .font(.headline)
                            }
                            .padding(.vertical, 16)
                            Spacer()
                        }
                    }
                }
                if !notes.isEmpty {
                    Section("Drafty (do przetworzenia)") {
                        ForEach(notes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                if note.isDraft {
                                    Label("Draft (offline)", systemImage: "wifi.slash")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                                Text(note.text)
                                Text(note.createdAt, style: .date)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet { modelContext.delete(notes[i]) }
                        }
                    }
                }
                Section {
                    Text("Wskazówka: podepnij skrót „Nowe przypomnienie głosowe” pod Back Tap (Ustawienia → Dostępność → Dotyk → Stuknij w tył) albo pod Action Button.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Przypomnij")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .fullScreenCover(isPresented: $showCapture) {
                CaptureView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: appState.startCaptureRequested) { _, requested in
                if requested {
                    appState.startCaptureRequested = false
                    showCapture = true
                }
            }
            .onOpenURL { url in
                if url.host == "capture" || url.absoluteString.contains("capture") {
                    showCapture = true
                }
            }
            .onAppear {
                if appState.startCaptureRequested {
                    appState.startCaptureRequested = false
                    showCapture = true
                }
            }
        }
    }
}
