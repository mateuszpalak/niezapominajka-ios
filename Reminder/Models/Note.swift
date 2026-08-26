import Foundation
import SwiftData

@Model
final class Note {
    var text: String
    var createdAt: Date
    /// Surowy transkrypt zapisany jako draft, gdy nie było internetu/API.
    var isDraft: Bool
    /// Rodzaj wykonanej akcji (CommandAction.rawValue) — wpis historii „Ostatnio”.
    var action: String?

    init(text: String, createdAt: Date = .now, isDraft: Bool = false, action: String? = nil) {
        self.text = text
        self.createdAt = createdAt
        self.isDraft = isDraft
        self.action = action
    }

    var commandAction: CommandAction? { action.flatMap(CommandAction.init(rawValue:)) }
}
