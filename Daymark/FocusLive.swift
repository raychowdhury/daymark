import ActivityKit
import Foundation

/// Keeps the Lock Screen / Dynamic Island timer in step with the stored focus timer.
@MainActor enum FocusLive {
    private static var last: FocusAttributes.ContentState?
    static func sync(_ timer: FocusTimer?, habit: Habit?, enabled: Bool) {
        let running = Activity<FocusAttributes>.activities
        guard enabled, let t = timer, t.status != "finished", let h = habit, let id = t.sessionId, ActivityAuthorizationInfo().areActivitiesEnabled else {
            last = nil
            for a in running { Task { await a.end(nil, dismissalPolicy:.immediate) } }
            return
        }
        let state = FocusAttributes.ContentState(endsAt:t.endsAt.map { Date(timeIntervalSince1970:$0 / 1000) }, remaining:t.remaining() / 1000, paused:t.status == "paused")
        if let current = running.first(where:{ $0.attributes.sessionId == id }) {
            guard state != last else { return }
            last = state
            Task { await current.update(ActivityContent(state:state, staleDate:state.endsAt)) }
        } else {
            for a in running { Task { await a.end(nil, dismissalPolicy:.immediate) } }
            last = state
            _ = try? Activity.request(attributes:FocusAttributes(habit:h.name, category:h.category, symbol:h.symbol, sessionId:id, minutes:Int(t.durationMs / 60000)),
                                      content:ActivityContent(state:state, staleDate:state.endsAt))
        }
    }
}
