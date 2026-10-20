import WidgetKit
import SwiftUI
import AppIntents

@main
struct AssistantWidgets: WidgetBundle {
    var body: some Widget {
        AssistantLockScreenWidget()
        AssistantControl()
    }
}

// MARK: - Widżet na ekranie blokady: „Asystent — Stuknij i mów”

struct AssistantEntry: TimelineEntry {
    let date: Date
}

struct AssistantProvider: TimelineProvider {
    func placeholder(in context: Context) -> AssistantEntry { AssistantEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (AssistantEntry) -> Void) {
        completion(AssistantEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AssistantEntry>) -> Void) {
        completion(Timeline(entries: [AssistantEntry(date: .now)], policy: .never))
    }
}

struct AssistantLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AssistantLockScreen", provider: AssistantProvider()) { _ in
            AssistantWidgetView()
        }
        .configurationDisplayName("Asystent")
        .description("Otwiera aplikację od razu w trybie słuchania.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct AssistantWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(URL(string: "niezapominajka://capture"))
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.22), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Asystent").font(.headline)
                    Text("Stuknij i mów").font(.caption).opacity(0.75)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label("Asystent", systemImage: "mic.fill")
        default:
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
        }
    }
}

// MARK: - Kontrolka (ekran blokady, Centrum sterowania, Action Button)

struct AssistantControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "software.plq.niezapominajka.assistant") {
            ControlWidgetButton(action: CaptureReminderIntent()) {
                Label("Asystent", systemImage: "mic.fill")
            }
        }
        .displayName("Asystent")
        .description("Otwiera aplikację od razu w trybie słuchania.")
    }
}
