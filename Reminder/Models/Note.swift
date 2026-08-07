import Foundation
import SwiftData

@Model
final class Note {
    var text: String
    var createdAt: Date
    /// Surowy transkrypt zapisany jako draft, gdy nie było internetu/API.
    var isDraft: Bool

    init(text: String, createdAt: Date = .now, isDraft: Bool = false) {
        self.text = text
        self.createdAt = createdAt
        self.isDraft = isDraft
    }
}
