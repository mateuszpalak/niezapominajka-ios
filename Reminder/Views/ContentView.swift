import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @State private var confirmClearHistory = false
    @StateObject private var capture = CaptureController()
    @State private var showSettings = false
    @AppStorage(AppSettings.Key.listenOnOpen) private var listenOnOpen = true
    @AppStorage(AppSettings.Key.preview) private var preview = false

    private let hints = ["„Przypomnij mi…”", "„Dodaj do zakupów…”", "„Zaplanuj spotkanie…”",
                         "„Wyślij SMS do…”", "„Zadzwoń do…”", "„Zanotuj…”"]

    var body: some View {
        VStack(spacing: 0) {
            // Ekran z kartami: bez nagłówka — na górze podyktowana treść.
            if capture.phase != .result { header }
            Group {
                if capture.phase == .result {
                    ScrollView { resultView.padding(.horizontal, 16) }
                        .scrollDismissesKeyboard(.interactively)
                } else {
                    phaseContent
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            if showButtons { buttonsRow.padding(.bottom, 8) }
            // Na ekranie z kartami tylko „Odrzuć” / „Gotowe” — bez mikrofonu.
            if capture.phase != .result { micArea }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: Binding(get: { capture.editingTranscript },
                                    set: { if !$0 { capture.cancelEditTranscript() } })) {
            EditTranscriptSheet(text: $capture.draft,
                                onCancel: { capture.cancelEditTranscript() },
                                onAnalyze: { capture.reanalyze() })
        }
        .sheet(item: $capture.compose, onDismiss: { capture.composeFinished(sent: false) }) { draft in
            MessageComposer(draft: draft) { sent in capture.composeFinished(sent: sent) }
                .ignoresSafeArea()
        }
        .onAppear {
            capture.attach(modelContext)
            consumeStartRequest()
            autoStart()
        }
        .onChange(of: appState.startCaptureRequested) { _, _ in consumeStartRequest() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { autoStart() }
        }
        .onOpenURL { url in
            if url.host == "capture" || url.absoluteString.contains("capture") {
                appState.startCaptureRequested = true
            }
        }
        .animation(.easeInOut(duration: 0.25), value: capture.phase)
        .animation(.easeInOut(duration: 0.25), value: capture.actions.map(\.status))
    }

    private var header: some View {
        HStack {
            Text("Asystent")
                .font(.system(size: 34, weight: .bold))
                .tracking(0.3)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ustawienia")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    // MARK: - Fazy

    @ViewBuilder
    private var phaseContent: some View {
        switch capture.phase {
        case .idle:
            idleView
        case .listening:
            listeningView
        case .processing:
            processingView
        case .ask:
            askView
        case .result:
            EmptyView()
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text(message)
                    .multilineTextAlignment(.center)
                if capture.keyProblem {
                    Button("Otwórz Ustawienia") { showSettings = true }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                } else {
                    Button("Spróbuj ponownie") { Task { await capture.startListening() } }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Text("Powiedz, co mam zrobić")
                    .font(.system(size: 22, weight: .semibold))
                Text("Możesz podać kilka poleceń naraz. Zapiszę, gdy skończysz mówić.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .frame(maxWidth: 280)
                FlowLayout(spacing: 8) {
                    ForEach(hints, id: \.self) { hint in
                        Text(hint)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(.label).opacity(0.8))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                }
                .frame(maxWidth: 320)
                .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            if !notes.isEmpty { historySection }
            Spacer(minLength: 0)
        }
    }

    private var listeningView: some View {
        let finishing = capture.silenceProgress > 0.4
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xFF3B30)).frame(width: 8, height: 8)
                    .modifier(Blink(period: 1.1))
                Text(finishing ? "KOŃCZĘ NAGRYWANIE…" : "SŁUCHAM…")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0xFF3B30))
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(capture.transcript)
                    .font(.system(size: 27, weight: .medium))
                    .tracking(-0.3)
                    .lineSpacing(6)
                Rectangle().fill(Color(hex: 0x007AFF)).frame(width: 3, height: 27)
                    .modifier(Blink(period: 0.9))
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            // Pasek ciszy (1,2 s) — po jego zapełnieniu nagranie samo się kończy.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule().fill(Color(hex: 0x007AFF))
                        .frame(width: geo.size.width * capture.silenceProgress)
                }
            }
            .frame(height: 4)
            .opacity(finishing ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var processingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(capture.lastTranscript)
                .font(.system(size: 19))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
            HStack(spacing: 10) {
                ProgressView()
                Text("Rozpoznaję polecenie…")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var askView: some View {
        if let ask = capture.ask {
            VStack(alignment: .leading, spacing: 14) {
                Text("„\(capture.lastTranscript)”")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                Text(ask.question)
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(Array(ask.options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { Divider().padding(.leading, 72) }
                        Button { capture.pickContact(option) } label: {
                            HStack(spacing: 12) {
                                Text(option.initials)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(LinearGradient(colors: [Color(hex: 0xA5A9B4), Color(hex: 0x858993)],
                                                               startPoint: .top, endPoint: .bottom), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.name).font(.system(size: 17)).foregroundStyle(Color(.label))
                                    Text(option.subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("„\(capture.lastTranscript)”")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { capture.beginEditTranscript() }
                Button("Edytuj", systemImage: "pencil") { capture.beginEditTranscript() }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .fontWeight(.semibold)
            }
            .padding(.leading, 4)
            .padding(.top, 12)
            .padding(.bottom, 4)

            ForEach(capture.actions) { action in
                ActionCard(
                    action: action,
                    choices: capture.choices,
                    countdown: capture.countdown,
                    editable: preview && action.status == .pending,
                    showsUndo: capture.actions.count > 1,
                    onUndo: { capture.undo(action.id) },
                    onText: { key, value in capture.setText(action.id, key: key, value: value) },
                    onDate: { capture.setDate(action.id, date: $0) },
                    onType: { capture.setType(action.id, to: $0) })
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Przyciski pod kartami

    private var showButtons: Bool {
        guard capture.phase == .result, !capture.editingTranscript else { return false }
        let settled = capture.actions.allSatisfy(\.isSettled)
        return !capture.pending.isEmpty || (settled && capture.countdown == nil)
    }

    private var buttonsRow: some View {
        let pending = capture.pending
        let unsafe = pending.first { !$0.command.action.isSafe }
        var primary = "Gotowe"
        if !pending.isEmpty {
            primary = (unsafe != nil && pending.count == 1) ? unsafe!.command.action.verb : "Zapisz"
            if capture.countdown != nil { primary += " teraz" }
        }
        return HStack(spacing: 10) {
            if pending.isEmpty && capture.canDiscard {
                Button { capture.discardAll() } label: {
                    Text("Odrzuć")
                        .foregroundStyle(Color(hex: 0xFF3B30))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            if !pending.isEmpty {
                Button { capture.cancelAll() } label: {
                    Text("Anuluj")
                        .foregroundStyle(Color(hex: 0x007AFF))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            Button {
                if pending.isEmpty { capture.finishBatch() } else { Task { await capture.executePending() } }
            } label: {
                Text(primary)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(hex: 0x007AFF), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .font(.system(size: 17, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Ostatnio

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("OSTATNIO")
                    .font(.system(size: 13))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Wyczyść") { confirmClearHistory = true }
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 16)
            .confirmationDialog("Wyczyścić całą historię?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
                Button("Wyczyść wszystko", role: .destructive) { clearHistory() }
            }
            // List zamiast VStack, żeby działał systemowy swipe w lewo do usunięcia.
            let recent = Array(notes.prefix(4))
            List {
                ForEach(recent) { note in
                    historyRow(note)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: Self.historyRowShape(index: recent.firstIndex(of: note) ?? 0, count: recent.count))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 58 }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { modelContext.delete(note) } label: {
                                Label("Usuń", systemImage: "trash")
                            }
                        }
                }
                .listRowSeparator(.hidden, edges: .top)
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, Self.historyRowHeight)
            .frame(height: Self.historyRowHeight * CGFloat(recent.count))
            .animation(.default, value: recent.count)
        }
    }

    private func historyRow(_ note: Note) -> some View {
        HStack(spacing: 12) {
            if let action = note.commandAction {
                ActionIcon(action: action, size: 30)
            } else {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.gray, in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(note.text).font(.system(size: 15)).lineLimit(1)
                Text(note.isDraft ? "Draft (offline)" : note.detail ?? note.commandAction?.label ?? "")
                    .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(note.createdAt, format: .relative(presentation: .named).locale(Locale(identifier: "pl_PL")))
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.historyRowHeight)
        .contextMenu {
            Button(role: .destructive) { modelContext.delete(note) } label: { Label("Usuń", systemImage: "trash") }
        }
    }

    private static let historyRowHeight: CGFloat = 56

    /// Zaokrąglenia jak w grupie iOS: góra pierwszego wiersza, dół ostatniego — przesunięty swipe'em wiersz zachowuje rogi.
    private static func historyRowShape(index: Int, count: Int) -> UnevenRoundedRectangle {
        let top: CGFloat = index == 0 ? 12 : 0
        let bottom: CGFloat = index == count - 1 ? 12 : 0
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: top)
    }

    private func clearHistory() {
        withAnimation { notes.forEach(modelContext.delete) }
    }

    // MARK: - Mikrofon

    private var micActive: Bool { capture.isListening }

    private var micArea: some View {
        VStack(spacing: 8) {
            ZStack {
                if micActive {
                    Circle().fill(Color(hex: 0xFF3B30))
                        .modifier(Pulse())
                }
                Button { capture.micTapped() } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(micColor, in: Circle())
                        .shadow(color: .black.opacity(0.16), radius: 7, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(micActive ? "Zakończ nasłuch" : "Zacznij mówić")
            }
            .frame(width: 72, height: 72)
            Text(micLabel)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(minHeight: 16)
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var micColor: Color {
        if micActive { return Color(hex: 0xFF3B30) }
        switch capture.phase {
        case .processing, .ask: return Color(hex: 0xC7C7CC)
        default: return Color(hex: 0x007AFF)
        }
    }

    private var micLabel: String {
        switch capture.phase {
        case .idle, .failed: return "Stuknij i mów"
        case .listening: return "Stuknij, aby zakończyć"
        case .processing: return ""
        case .ask: return "Wybierz kontakt"
        case .result: return ""
        }
    }

    // MARK: - Start z intentu / URL / po otwarciu

    private func consumeStartRequest() {
        guard appState.startCaptureRequested else { return }
        appState.startCaptureRequested = false
        startWhenActive()
    }

    /// „Słuchaj po otwarciu”: nasłuch rusza sam, gdy aplikacja staje się aktywna na ekranie startowym.
    private func autoStart() {
        guard listenOnOpen, capture.phase == .idle, !showSettings, capture.compose == nil else { return }
        startWhenActive()
    }

    private func startWhenActive() {
        Task {
            // Scena bywa nieaktywna przy starcie przez URL — poczekaj, zanim
            // włączysz mikrofon (inaczej zawiesza przejście między aplikacjami).
            var waited = 0
            while scenePhase != .active && waited < 20 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            if capture.phase != .listening { await capture.startListening() }
        }
    }
}

// MARK: - Pomocnicze widoki

/// Edycja treści polecenia — arkusz z „Anuluj” / „Analizuj” w pasku, jak w systemowych aplikacjach.
struct EditTranscriptSheet: View {
    @Binding var text: String
    var onCancel: () -> Void
    var onAnalyze: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Polecenie", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                } footer: {
                    Text("Popraw treść, a asystent przeanalizuje polecenie jeszcze raz. Zapisane już elementy zostaną zastąpione.")
                }
            }
            .navigationTitle("Edytuj polecenie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analizuj", action: onAnalyze)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ActionIcon: View {
    let action: CommandAction
    let size: CGFloat
    var body: some View {
        Image(systemName: action.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(action.color, in: RoundedRectangle(cornerRadius: size / 4))
    }
}

private struct Blink: ViewModifier {
    let period: Double
    @State private var on = true
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) { on = false }
            }
    }
}

private struct Pulse: ViewModifier {
    @State private var expanded = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(expanded ? 1.6 : 1)
            .opacity(expanded ? 0 : 0.35)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { expanded = true }
            }
    }
}

/// Prosty układ „chipów” zawijanych do kolejnych wierszy.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            // Wyśrodkuj każdy wiersz.
            let rowWidth = result.rowWidths[result.rows[index]]
            let offset = (bounds.width - rowWidth) / 2
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX + offset, y: bounds.minY + frame.minY),
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews)
        -> (size: CGSize, frames: [CGRect], rows: [Int], rowWidths: [CGFloat]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = [], rows: [Int] = [], rowWidths: [CGFloat] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, row = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rowWidths.append(x - spacing)
                x = 0; y += rowHeight + spacing; rowHeight = 0; row += 1
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rows.append(row)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        rowWidths.append(max(0, x - spacing))
        return (CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight), frames, rows, rowWidths)
    }
}
