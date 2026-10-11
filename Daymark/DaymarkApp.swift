import SwiftUI
import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
@main struct DaymarkApp: App {
    @StateObject private var store = HabitStore()
    private let notifications = NotificationPresenter()
    init() { UNUserNotificationCenter.current().delegate = notifications }
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(Palette.teal)
                .onChange(of:scenePhase) { _, phase in if phase == .active { store.refresh() } }
        }
    }
}
