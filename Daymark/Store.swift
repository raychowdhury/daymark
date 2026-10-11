import Foundation
import SwiftUI
import UserNotifications

@MainActor final class HabitStore: ObservableObject {
    @Published var data = AppData()
    @Published var error: String?
    @Published var reminders = false
    @Published var permission = UNAuthorizationStatus.notDetermined
    /// Set at a good moment to ask for a rating; RootView asks iOS and resets it.
    @Published var reviewMoment = false
    private var clock: Timer?
    private var loadBlocked = false
    private let url: URL
    init(url: URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Daymark.json")) {
        self.url = url
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            if FileManager.default.fileExists(atPath:url.path) { data = try JSONDecoder().decode(AppData.self,from:Data(contentsOf:url)) }
        } catch { loadBlocked = true; self.error = "Your saved data could not be loaded. Import a backup before making changes. \(error.localizedDescription)" }
        Day.mondayFirst = data.prefs.mondayFirst
        NotificationCenter.default.addObserver(forName:NSUbiquitousKeyValueStore.didChangeExternallyNotification, object:cloud, queue:.main) { [weak self] _ in Task { @MainActor in self?.pullCloud() } }
        if data.prefs.iCloud { cloud.synchronize(); pullCloud() }
        Task { let settings = await UNUserNotificationCenter.current().notificationSettings(); permission = settings.authorizationStatus; reminders = data.remindersEnabled && permission == .authorized; scheduleReminders() }
        refresh()
        clock = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in Task { @MainActor in if self?.data.timer?.status == "running" { self?.refresh() } } }
    }
    func save() {
        guard !loadBlocked else { return }
        data.updatedAt = Date().timeIntervalSince1970 * 1000
        Day.mondayFirst = data.prefs.mondayFirst
        do { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted,.sortedKeys]; try e.encode(data).write(to:url,options:.atomic) } catch { self.error = error.localizedDescription }
        pushCloud()
        FocusLive.sync(data.timer, habit:data.habits.first { $0.id == data.timer?.id }, enabled:data.prefs.liveActivity)
    }
    func amount(_ h: Habit, _ date: Date = Date()) -> Int { data.records[Day.key(date)]?[h.id] ?? 0 }
    func complete(_ h: Habit, _ date: Date = Date()) -> Bool { amount(h,date) >= h.target }
    func setAmount(_ h: Habit, _ value: Int, _ date: Date = Date()) {
        let key = Day.key(date), was = complete(h,date)
        data.records[key,default:[:]][h.id] = max(0,min(99999,value))
        if !complete(h,date) { data.completedAt[key]?[h.id] = nil } else if !was { data.completedAt[key,default:[:]][h.id] = Date().timeIntervalSince1970 * 1000 }
        save()
        if !was && complete(h,date) && key == Day.key(Date()) && [7, 30, 100].contains(streak(h)) { reviewMoment = true }
    }
    /// When the target was reached, if it was reached on that same day (not a later catch-up).
    func doneAt(_ h: Habit, _ date: Date = Date()) -> Date? {
        guard let ms = data.completedAt[Day.key(date)]?[h.id] else { return nil }
        let d = Date(timeIntervalSince1970:ms / 1000)
        return Day.key(d) == Day.key(date) ? d : nil
    }
    func note(_ h: Habit, _ date: Date = Date()) -> String { data.notes[Day.key(date)]?[h.id] ?? "" }
    func setNote(_ h: Habit, _ value: String, _ date: Date = Date()) { data.notes[Day.key(date),default:[:]][h.id] = String(value.prefix(2000)); save() }
    func weekly(_ h: Habit, _ date: Date = Date()) -> Int { Day.week(date).filter { $0 <= date && h.due($0) && complete(h,$0) }.count }
    enum DayState { case full, partial, none }
    func dailyDue(_ date: Date) -> [Habit] { data.habits.filter { $0.weeklyGoal == nil && $0.due(date) } }
    func dayState(_ date: Date) -> DayState {
        let due = dailyDue(date), done = due.filter { complete($0,date) }.count
        return done == 0 ? .none : done == due.count ? .full : .partial
    }
    /// Completed vs. scheduled days over the last `days` days, today included.
    func consistency(_ h: Habit, days: Int = 30) -> (done: Int, due: Int) {
        let dates = (0..<days).compactMap { Calendar.current.date(byAdding:.day,value:-$0,to:Date()) }.filter { h.due($0) }
        return (dates.filter { complete(h,$0) }.count, dates.count)
    }
    func weekSessions(_ date: Date = Date()) -> [Session] { let keys = Set(Day.week(date).map(Day.key)); return data.sessions.filter { keys.contains($0.day) } }
    func streak(_ h: Habit) -> Int {
        guard h.weeklyGoal == nil else { return 0 }
        var result = 0
        for offset in 0..<3660 {
            guard let day = Calendar.current.date(byAdding:.day,value:-offset,to:Date()), Day.key(day) >= h.createdAt else { break }
            if !h.due(day) { continue }
            if complete(h,day) { result += 1 } else if offset != 0 { break }
        }
        return result
    }
    func upsert(_ h: Habit) { if let i = data.habits.firstIndex(where:{$0.id == h.id}) { data.habits[i] = h } else { data.habits.append(h) }; save(); scheduleReminders() }
    func finishOnboarding(adding habits: [Habit] = []) { data.habits += habits; data.onboarded = true; save(); scheduleReminders() }
    func restartArchived(_ h: Habit) { var copy = h; copy.id = UUID().uuidString; copy.createdAt = Day.key(Date()); copy.archivedAt = nil; upsert(copy) }
    func setSessionNote(_ id: String, _ value: String) { if let i = data.sessions.firstIndex(where:{$0.id == id}) { data.sessions[i].note = String(value.prefix(2000)); save() } }
    func erase() { UNUserNotificationCenter.current().removeAllPendingNotificationRequests(); data = AppData(); loadBlocked = false; reminders = false; save() }
    func archive(_ h: Habit) { guard let i = data.habits.firstIndex(where:{$0.id == h.id}) else { return }; data.habits[i].archivedAt = Day.key(Date()); save(); scheduleReminders() }
    func finish(_ outcome: String, at end: Double? = nil) {
        guard var t = data.timer, t.status != "finished" else { return }
        let remaining = t.remaining()
        let session = Session(sessionId:t.sessionId ?? UUID().uuidString,habitId:t.id,day:t.day,startedAt:t.startedAt,endedAt:end ?? Date().timeIntervalSince1970*1000,durationMs:t.durationMs,elapsedMs:max(0,t.durationMs - remaining),outcome:outcome,note:"",logged:t.logged)
        if !data.sessions.contains(where:{$0.id == session.id}) { data.sessions.insert(session,at:0) }
        t.sessionId = session.id; t.status = "finished"; t.remainingMs = outcome == "completed" ? 0 : remaining; t.endsAt = nil; data.timer = t
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:["focus"]); save()
    }
    func refresh() {
        if let t = data.timer, t.status == "running", t.remaining() <= 0 { finish("completed",at:t.endsAt) }
        FocusLive.sync(data.timer, habit:data.habits.first { $0.id == data.timer?.id }, enabled:data.prefs.liveActivity)   // also covers relaunch mid-session
        objectWillChange.send()
    }
    func start(_ h: Habit, minutes: Int, logCurrent: Bool = false) {
        if let t = data.timer, t.status != "finished" { finish("replaced") }
        if logCurrent { logTimer() }
        let ms = Double(max(1,min(1440,minutes))) * 60000; let now = Date().timeIntervalSince1970*1000
        data.timer = FocusTimer(id:h.id,day:Day.key(Date()),durationMs:ms,remainingMs:ms,endsAt:now+ms,status:"running",sessionId:UUID().uuidString,startedAt:now); save(); scheduleFocus()
    }
    func pauseResume() {
        guard var t = data.timer, t.status != "finished" else { return }; refresh(); guard data.timer?.status != "finished" else { return }
        if t.status == "running" { t.remainingMs = t.remaining(); t.endsAt = nil; t.status = "paused" } else { t.endsAt = Date().timeIntervalSince1970*1000+t.remainingMs; t.status = "running" }
        data.timer = t; save(); scheduleFocus()
    }
    func dismissTimer() { data.timer = nil; save(); UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:["focus"]) }
    func restart() { guard let t = data.timer, let h = data.habits.first(where:{$0.id == t.id}) else { return }; finish("restarted"); start(h,minutes:Int(t.durationMs/60000)) }
    func logTimer() {
        guard var t = data.timer, t.canLog, let h = data.habits.first(where:{$0.id == t.id}), let date = Day.date(t.day) else { return }
        setAmount(h,h.isMinutes ? amount(h,date)+t.focusedMinutes : max(amount(h,date),h.target),date)
        t.logged = true; data.timer = t
        if let i = data.sessions.firstIndex(where:{$0.id == t.sessionId}) { data.sessions[i].logged = true }; save()
        if data.sessions.filter(\.logged).count == 3 { reviewMoment = true }
    }
    func requestReminders() async {
        do { reminders = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]); permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus; if !reminders { error = "Notifications are disabled. Enable them in iPhone Settings to receive reminders." }; data.remindersEnabled = reminders; save(); scheduleReminders() } catch { self.error = error.localizedDescription }
    }
    func scheduleReminders() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        scheduleFocus()
        guard reminders else { return }
        var count = 0
        for h in data.habits where h.archivedAt == nil && h.reminder ?? true {
            guard let time = h.startTime, time.count == 5 else { continue }; let bits = time.split(separator:":").compactMap{Int($0)}; guard bits.count == 2 else { continue }
            // Seven flexible opportunities for weekly goals; fixed days for daily goals. Limit to iOS's 64 pending requests.
            for day in h.weeklyGoal == nil ? h.days : Array(0...6) {
                guard count < 63 else { continue }; count += 1
                let lead = data.prefs.leadMinutes, minute = bits[0] * 60 + bits[1] - lead
                var components = DateComponents(); components.weekday = (minute < 0 ? (day + 6) % 7 : day) + 1; components.hour = (minute + 1440) % 1440 / 60; components.minute = (minute + 1440) % 60
                let content = UNMutableNotificationContent(); content.title = h.name; content.body = lead > 0 ? "Starts in \(lead) min." : "A little progress starts now."; content.sound = .default
                center.add(UNNotificationRequest(identifier:"habit-\(h.id)-\(day)",content:content,trigger:UNCalendarNotificationTrigger(dateMatching:components,repeats:true)))
            }
        }
    }
    func scheduleFocus() {
        let center = UNUserNotificationCenter.current(); center.removePendingNotificationRequests(withIdentifiers:["focus"])
        guard reminders, let t = data.timer, t.status == "running", t.remaining() > 0 else { return }
        let c = UNMutableNotificationContent(); c.title = "Session complete"; c.body = "Open Daymark to log your progress."; c.sound = data.prefs.endSound ? .default : nil
        center.add(UNNotificationRequest(identifier:"focus",content:c,trigger:UNTimeIntervalNotificationTrigger(timeInterval:max(1,t.remaining()/1000),repeats:false)))
    }
    func backup() -> Data { (try? JSONEncoder().encode(data)) ?? Data() }
    func importBackup(_ bytes: Data) throws {
        var candidate = try validated(bytes)
        candidate.prefs = data.prefs   // device settings stay as they are
        apply(candidate)
    }
    func validated(_ bytes: Data) throws -> AppData {
        guard bytes.count < 10_000_000 else { throw ImportError.invalid }
        let candidate = try JSONDecoder().decode(AppData.self,from:bytes)
        let ids = Set(candidate.habits.map(\.id)); let today = Day.key(Date())
        guard candidate.schema == 1, ids.count == candidate.habits.count, candidate.habits.count <= 500 else { throw ImportError.invalid }
        for h in candidate.habits {
            guard !h.id.isEmpty, !h.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, h.name.count <= 200, ["check","count"].contains(h.type), (1...99999).contains(h.target), !h.days.isEmpty, h.days.allSatisfy({(0...6).contains($0)}), Day.date(h.createdAt) != nil, h.createdAt <= today, h.weeklyGoal == nil || (1...7).contains(h.weeklyGoal!) else { throw ImportError.invalid }
            if let a = h.archivedAt { guard Day.date(a) != nil, a >= h.createdAt else { throw ImportError.invalid } }
            if let time = h.startTime { let b = time.split(separator:":").compactMap{Int($0)}; guard time.count == 5, b.count == 2, (0...23).contains(b[0]), (0...59).contains(b[1]) else { throw ImportError.invalid } }
        }
        for (day, entries) in candidate.records { guard Day.date(day) != nil, day <= today, entries.allSatisfy({ids.contains($0.key) && (0...99999).contains($0.value)}) else { throw ImportError.invalid } }
        for (day, entries) in candidate.notes { guard Day.date(day) != nil, day <= today, entries.allSatisfy({ids.contains($0.key) && $0.value.count <= 2000}) else { throw ImportError.invalid } }
        guard Set(candidate.sessions.map(\.id)).count == candidate.sessions.count else { throw ImportError.invalid }
        for s in candidate.sessions { guard ids.contains(s.habitId), Day.date(s.day) != nil, s.durationMs.isFinite, s.elapsedMs.isFinite, s.endedAt.isFinite, (60000...86400000).contains(s.durationMs), s.endedAt >= 0, s.endedAt <= Date().timeIntervalSince1970*1000 + 86400000, s.day <= today, ["completed","stopped","restarted","replaced"].contains(s.outcome), s.startedAt == nil || (s.startedAt!.isFinite && s.startedAt! >= 0 && s.startedAt! <= s.endedAt), s.elapsedMs >= 0, s.elapsedMs <= s.durationMs, s.note.count <= 2000 else { throw ImportError.invalid } }
        if let t = candidate.timer { guard ids.contains(t.id), Day.date(t.day) != nil, t.durationMs.isFinite, (60000...86400000).contains(t.durationMs), t.remainingMs.isFinite, (0...t.durationMs).contains(t.remainingMs), ["running","paused","finished"].contains(t.status), t.status != "running" || (t.endsAt?.isFinite == true) else { throw ImportError.invalid } }
        for (day, entries) in candidate.completedAt { guard Day.date(day) != nil, entries.allSatisfy({ ids.contains($0.key) && $0.value.isFinite && $0.value >= 0 }) else { throw ImportError.invalid } }
        let p = candidate.prefs
        guard (0...120).contains(p.leadMinutes), (1...180).contains(p.defaultMinutes), ["system","light","dark"].contains(p.appearance) else { throw ImportError.invalid }
        return candidate
    }
    private func apply(_ candidate: AppData) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests(); data = candidate; loadBlocked = false; refresh(); save(); scheduleReminders(); scheduleFocus()
    }

    // MARK: iCloud
    // ponytail: whole-file, newest-copy-wins sync through iCloud key-value storage (1 MB cap, no per-record merge).
    // Edits made on two devices while both are offline keep only the newer copy. Move to CloudKit records if that bites.
    private let cloud = NSUbiquitousKeyValueStore.default
    private let cloudKey = "daymark"
    var cloudCopy: AppData? { cloud.data(forKey:cloudKey).flatMap { try? validated($0) } }
    private func pushCloud() {
        guard data.prefs.iCloud, let bytes = try? JSONEncoder().encode(data) else { return }
        guard bytes.count < 1_000_000 else { error = "Your data is too large for iCloud sync. Export a backup instead."; return }
        cloud.set(bytes, forKey:cloudKey); cloud.synchronize()
    }
    private func pullCloud() {
        guard data.prefs.iCloud, var remote = cloudCopy, remote.updatedAt > data.updatedAt else { return }
        remote.prefs.iCloud = true
        apply(remote)
    }
    /// Turns sync on. `useCloud` picks the iCloud copy over this iPhone's data when both exist.
    func enableCloud(useCloud: Bool) {
        if useCloud, var remote = cloudCopy { remote.prefs.iCloud = true; apply(remote) } else { data.prefs.iCloud = true; save() }
    }
    func disableCloud() { data.prefs.iCloud = false; save() }

    // MARK: CSV
    func csv() -> Data {
        func cell(_ s: String) -> String { s.contains(where:{ ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of:"\"", with:"\"\"") + "\"" : s }
        var rows = ["date,habit,category,amount,target,unit,complete,completed_at,note"]
        for day in Set(data.records.keys).union(data.notes.keys).sorted() {
            guard let date = Day.date(day) else { continue }
            for h in data.habits where data.records[day]?[h.id] != nil || data.notes[day]?[h.id] != nil {
                let done = doneAt(h, date).map { $0.formatted(.iso8601) } ?? ""
                rows.append([day, cell(h.name), cell(h.category), "\(amount(h,date))", "\(h.target)", cell(h.unit), complete(h,date) ? "yes" : "no", done, cell(note(h,date))].joined(separator:","))
            }
        }
        return Data((rows.joined(separator:"\n") + "\n").utf8)
    }
}
enum ImportError: LocalizedError { case invalid; var errorDescription: String? { "This backup contains unsupported or invalid data. Your current records have been kept." } }
