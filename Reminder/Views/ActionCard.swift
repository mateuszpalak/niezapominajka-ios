import SwiftUI

/// Karta jednej akcji: nagłówek (typ, tytuł, status / pierścień odliczania), przełącznik typu
/// w trybie podglądu i wiersze pól („Treść”, „Kiedy”, „Lista”…).
struct ActionCard: View {
    let action: PlannedAction
    let choices: ChoiceSource
    let countdown: CaptureController.Countdown?
    let editable: Bool
    /// Przy jednej karcie cofanie jest pod „Odrzuć”; przy kilku — osobno na karcie.
    var showsUndo = true
    var onUndo: () -> Void
    var onText: (String, String) -> Void
    var onDate: (Date?) -> Void
    var onType: (CommandAction) -> Void

    private var kind: CommandAction { action.command.action }
    private var undone: Bool { action.status == .undone }

    var body: some View {
        VStack(spacing: 0) {
            header
            if editable, [.reminder, .event, .note].contains(kind) {
                Picker("Typ", selection: Binding(get: { kind }, set: { onType($0) })) {
                    Text("Przypomnienie").tag(CommandAction.reminder)
                    Text("Wydarzenie").tag(CommandAction.event)
                    Text("Notatka").tag(CommandAction.note)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            Divider()
            ForEach(Array(action.fields(choices).enumerated()), id: \.element.id) { index, field in
                if index > 0 { Divider().padding(.leading, 16) }
                fieldRow(field)
            }
            if case .failed(let message) = action.status {
                Divider()
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xFF3B30))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(undone ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.3), value: undone)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ActionIcon(action: kind, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.label)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(action.cardTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .strikethrough(undone)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
    }

    @ViewBuilder
    private var trailing: some View {
        switch action.status {
        case .pending:
            if let countdown, !kind.isSafe {
                CountdownRing(countdown: countdown)
            }
        case .running:
            ProgressView()
        case .done:
            VStack(alignment: .trailing, spacing: 6) {
                Label(kind.doneLabel, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x34C759))
                if showsUndo, kind.isSafe, action.undo != nil {
                    Button(action: onUndo) {
                        Label("Cofnij", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
        case .undone:
            Text("Cofnięto")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        case .failed:
            Text("Błąd")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFF3B30))
        }
    }

    private func fieldRow(_ field: CardField) -> some View {
        HStack(spacing: 12) {
            Text(field.label)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            fieldValue(field)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func fieldValue(_ field: CardField) -> some View {
        let blue = Color(hex: 0x007AFF)
        if !editable || field.kind == .readOnly {
            Text(field.value.isEmpty ? "—" : field.value)
                .font(.system(size: 15))
                .lineSpacing(2)
                .padding(.vertical, 11)
        } else {
            switch field.kind {
            case .text, .readOnly:
                TextField(field.label, text: Binding(get: { field.value }, set: { onText(field.key, $0) }), axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(blue)
                    .padding(.vertical, 11)
            case .date:
                if let date = action.command.dueDateParsed {
                    DatePicker(field.label, selection: Binding(get: { date }, set: { onDate($0) }),
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "pl_PL"))
                        .padding(.vertical, 5)
                } else {
                    Button("Bez terminu") { onDate(Self.nextFullHour()) }
                        .font(.system(size: 15))
                        .foregroundStyle(blue)
                        .padding(.vertical, 11)
                }
            case .choice(let options):
                // Natywne menu wyboru.
                Menu {
                    Picker(field.label, selection: Binding(get: { field.value }, set: { onText(field.key, $0) })) {
                        ForEach(options, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(field.value.isEmpty ? "—" : field.value)
                            .font(.system(size: 15))
                            .foregroundStyle(blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private static func nextFullHour() -> Date {
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return calendar.dateInterval(of: .hour, for: next)?.start ?? next
    }
}

/// Pierścień odliczania z sekundami (SMS / połączenie).
private struct CountdownRing: View {
    let countdown: CaptureController.Countdown

    var body: some View {
        let blue = Color(hex: 0x007AFF)
        ZStack {
            Circle().stroke(Color(.systemGray5), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0, countdown.left / countdown.total))
                .stroke(blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(countdown.left.rounded(.up)))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(blue)
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel("Wykonam za \(Int(countdown.left.rounded(.up))) s")
    }
}
