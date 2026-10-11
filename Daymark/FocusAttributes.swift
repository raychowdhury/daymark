import ActivityKit
import Foundation

/// Shared by the app and the widget extension: one Live Activity per focus session.
struct FocusAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date?          // set while running
        var remaining: TimeInterval
        var paused: Bool
    }
    var habit: String
    var category: String
    var symbol: String
    var sessionId: String
    var minutes: Int
}
