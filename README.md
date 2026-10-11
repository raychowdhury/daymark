# Daymark for iPhone

A native SwiftUI habit tracker with a calm teal, indigo, and coral palette, adaptive dark mode, SF Symbols, system navigation, and accessible text. Requires iOS 17 or later. No third-party packages, backend, login, or web view.

## Open and run

1. Unzip this folder on a Mac with Xcode 15 or later.
2. Open **Daymark.xcodeproj**. Select the **Daymark** scheme.
3. Select an iPhone simulator and press Run (⌘R).
4. For your own iPhone, select your connected iPhone and Run. Signing is automatic with team F5MY9BC25S and bundle identifier `com.raychowdhury.daymark`. Follow Xcode's instructions for device trust and Developer Mode if shown.
5. Run the included unit tests with ⌘U.

Builds without warnings and passes its unit tests in Xcode 27 on the iOS 26.5 simulator. It is source code, not a signed IPA or an App Store release; complete the manual checks below before release.

## Features

Built to the Daymark design canvas (light and dark tokens, SF Pro, SF Symbols, 44 pt targets).

- Welcome and first habit: optional name with a live greeting preview, suggested starters, or create your own. No notification prompt during setup.
- Today: greeting, week strip (all done, partly done, none), daily summary that leaves weekly goals out, habit cards with check, +1, progress rails, "Starts in…" countdowns, notes, and an active-session bar. Earlier check-in picks any past day.
- Focus: compact setup sheet (5/15/25/45 min or custom 1–180), then a dark full-screen timer. Pause, resume, restart, end. Finishing never changes a habit; Log is the only path, works for stopped sessions too, and can be used once. Replacing an unfinished session asks: log it first, discard, or keep going.
- Habits: grouped by Body / Mind / Life with streaks; form with type, chosen days or days per week, scheduled start, and a per-habit reminder (permission is requested only then). Archive keeps history; Restart begins a fresh streak.
- Notes: one per habit per day, plus notes on logged sessions, up to 2,000 characters.
- Progress: last 7 days, current streak, focus this week, weekly goals, 30-day consistency.
- Sessions: grouped by day with active minutes and logged status.
- Settings: name; reminder switch, permission status and lead time; default focus length, Lock Screen timer, end-of-session sound; week start (Monday or Sunday) and appearance; iCloud sync; CSV history export; JSON backup export/import; erase all data.
- Lock Screen and Dynamic Island: a Live Activity counts down the running focus session (the `DaymarkWidgets` extension).
- Check-off cards show when a habit was completed ("Done 7:52 AM").

## Move data from the web tracker

In the web app, export your JSON backup. Transfer it to Files on your iPhone, then use Daymark → Today → Settings → Import backup. Export the current iPhone data before replacing it if needed. The native app accepts Daymark schema-1 backups, including old backups without session history, and uses the same string habit IDs, local date keys, and millisecond timestamps. The native `remindersEnabled`, `completedAt`, `prefs` and `updatedAt` fields are additional metadata; the web version can ignore them. There is **no automatic synchronization** between web and iPhone. Native edits should be moved through a backup.

## Reminders and background time

Enable reminders in Settings to request notification permission. Scheduled daily habits use their chosen weekdays; flexible weekly habits have daily opportunities. At most 63 habit requests are scheduled, reserving a slot for a timer alert; habits later in the list may not receive reminders if the limit is exceeded. Timers update when the app returns to the foreground, using their stored deadline. Alerts follow iOS notification permission and Focus settings and are not a guaranteed alarm. No background execution entitlement is needed.

## Data and privacy

Records are stored atomically in the app's Application Support directory. No analytics, advertising, or account service is included. iCloud sync is off by default; when on, the whole data file is copied through your iCloud account's key-value storage (1 MB limit) and the newest copy wins if two devices change at once. Turning it on when iCloud already holds data asks which copy to keep. Export backups regularly; deleting the app removes local data. Notification content contains habit names, which may appear on the lock screen depending on your iPhone settings.

## Verify in Xcode before release

Build, run the tests, and check light/dark appearance, VoiceOver, large accessibility text, small iPhones, rotation, and the native file picker. Check timer completion after backgrounding/relaunch, paused elapsed time, notification permissions, midnight/week boundaries, archives, and imported real backups. TestFlight or App Store distribution needs your Apple Developer account and a separate distribution setup.

## Source map

- `Models.swift`: schema, tolerant backup decoding, dates, design tokens.
- `Store.swift`: persistence, import validation, metrics, timers, notifications.
- `Views.swift`: root tabs, shared components, onboarding, settings.
- `TodayView.swift`: Today, habit cards, session bar, earlier check-in.
- `FocusViews.swift`: focus setup sheet, full-screen timer, replace dialog.
- `HabitViews.swift`: habits list, habit form, note editor, notes list.
- `InsightViews.swift`: Progress and Sessions.
- `DaymarkApp.swift`: app entry point, foreground reconciliation, in-app notification banners.
- `FocusAttributes.swift`, `FocusLive.swift`: Live Activity data (shared with the widget) and its start/update/end.
- `DaymarkWidgets/`: widget extension with the Lock Screen and Dynamic Island views.
- `Daymark.entitlements`: iCloud key-value storage.
- `DaymarkTests.swift`: deadlines, pauses, weeks, archives, backups, logging and replace rules.

Built with standard SwiftUI and UserNotifications APIs. References:
- https://developer.apple.com/documentation/swiftui
- https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app

## Website

`docs/` holds the support and privacy pages linked from the App Store listing, served by GitHub Pages at https://raychowdhury.github.io/daymark/.
