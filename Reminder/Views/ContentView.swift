import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @StateObject private var capture = CaptureController()
    @State private var showSettings = false

    private let hints = ["„Przypomnij mi…”", "„Zanotuj…”", "„Dodaj do zakupów…”", "„Wyślij SMS do…”", "„Zadzwoń do…”"]

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                phaseContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if capture.phase == .idle, !notes.isEmpty {
                    historySection
                }
            }
            .padding(.horizontal, 20)
            micArea
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Ustawienia")
            }
        }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            capture.attach(modelContext)
            consumeStartRequest()
        }
        .onChange(of: appState.startCaptureRequested) { _, _ in consumeStartRequest() }
        .onOpenURL { url in
            if url.host == "capture" || url.absoluteString.contains("capture") {
                appState.startCaptureRequested = true
            }
        }
        .animation(.easeInOut(duration: 0.25), value: capture.phase)
    }

    // MARK: - Fazy

    @ViewBuilder
    private var phaseContent: some View {
        switch capture.phase {
        case .idle:
            idleView
        case .listening:
            listeningView
        case .interpreting:
            processingView
        case .preview(let command):
            resultCard(command)
        case .done(let text):
            statusView(symbol: "checkmark.circle.fill", color: .green, text: text)
        case .failed(let message):
            VStack(spacing: 14) {
                statusView(symbol: "exclamationmark.triangle.fill", color: .orange, text: message)
                Button("Spróbuj ponownie") { Task { await capture.startListening() } }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Text("Powiedz, co mam zrobić")
                .font(.system(size: 22, weight: .semibold))
            Text("Notatka, przypomnienie, wydarzenie, zakupy, SMS albo telefon — po prostu mów.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 260)
            FlowLayout(spacing: 8) {
                ForEach(hints, id: \.self) { hint in
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(Color(.label).opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                }
            }
            .frame(maxWidth: 300)
            .padding(.top, 14)
        }
        .multilineTextAlignment(.center)
    }

    private var listeningView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                    .modifier(Blink(period: 1.1))
                Text("SŁUCHAM…")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 2) {
                Text(capture.transcript)
                    .font(.system(size: 26, weight: .medium))
                    .tracking(-0.3)
                    .lineSpacing(6)
                Rectangle().fill(.tint).frame(width: 3, height: 26)
                    .modifier(Blink(period: 0.9))
            }
            .frame(minHeight: 140, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var processingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(capture.lastTranscript)
                .font(.body)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ProgressView()
                Text("Przetwarzam…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultCard(_ command: InterpretedCommand) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("„\(capture.lastTranscript)”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ActionIcon(action: command.action, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(command.action.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(command.title)
                            .font(.headline)
                    }
                }
                let detail = command.detailLine
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color(.label).opacity(0.8))
                }
                HStack(spacing: 10) {
                    Button { Task { await capture.execute(command) } } label: {
                        Text("Wykonaj").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { capture.cancel() } label: {
                        Text("Anuluj").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .fontWeight(.semibold)
                .padding(.top, 2)
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusView(symbol: String, color: Color, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(color)
            Text(text)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Ostatnio

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OSTATNIO")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(notes.prefix(3).enumerated()), id: \.element.persistentModelID) { index, note in
                    historyRow(note)
                    if index < min(notes.count, 3) - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.bottom, 8)
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
                Text(note.text).font(.subheadline).lineLimit(1)
                Text(note.isDraft ? "Draft (offline)" : note.commandAction?.label ?? "")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(note.createdAt, format: .relative(presentation: .named))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contextMenu {
            Button(role: .destructive) { modelContext.delete(note) } label: { Label("Usuń", systemImage: "trash") }
        }
    }

    // MARK: - Mikrofon

    private var micArea: some View {
        VStack(spacing: 10) {
            ZStack {
                if capture.isListening {
                    Circle().fill(.red)
                        .modifier(Pulse())
                }
                Button { capture.micTapped() } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(capture.isListening ? Color.red : Color.accentColor, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 7, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(capture.isListening ? "Zakończ nasłuch" : "Zacznij mówić")
            }
            .frame(width: 76, height: 76)
            Text(micLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var micLabel: String {
        switch capture.phase {
        case .listening: return "Stuknij, aby zakończyć"
        case .idle, .done, .failed: return "Stuknij i mów"
        default: return " "
        }
    }

    // MARK: - Start z intentu / URL

    private func consumeStartRequest() {
        guard appState.startCaptureRequested else { return }
        appState.startCaptureRequested = false
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

private struct ActionIcon: View {
    let action: CommandAction
    let size: CGFloat
    var body: some View {
        Image(systemName: action.symbol)
            .font(.system(size: size / 2, weight: .semibold))
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
