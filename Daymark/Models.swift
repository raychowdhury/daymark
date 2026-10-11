import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct Profile: Codable { var name = "" }
struct Habit: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var category = "Mind"
    var icon = "focus"
    var color = "sage"
    var type = "check"
    var target = 1
    var unit = "times"
    var days = [0,1,2,3,4,5,6]
    var createdAt = Day.key(Date())
    var archivedAt: String?
    var weeklyGoal: Int?
    var startTime: String?
    var reminder: Bool?   // nil = older data: follows the global switch
    var symbol: String {
        ["walk":"figure.walk", "book":"book", "water":"drop", "focus":"scope", "moon":"moon", "heart":"heart", "dumbbell":"dumbbell", "leaf":"leaf", "sun":"sun.max", "spark":"sparkles", "coffee":"cup.and.saucer"][icon] ?? "checkmark"
    }
    var tint: Color {
        switch color { case "blue": return Palette.indigo; case "clay": return Palette.coral; case "lavender": return .purple; case "gold": return .orange; case "rose": return .pink; default: return Palette.teal }
    }
    var wash: Color {
        switch color { case "blue": return Palette.indigoTint; case "clay": return Palette.coralTint; case "sage": return Palette.tealTint; default: return tint.opacity(0.15) }
    }
    var isMinutes: Bool { type == "count" && ["min","mins","minute","minutes"].contains(unit.lowercased()) }
    /// "21:30" → "9:30 PM" in the user's locale.
    var startLabel: String? {
        guard let s = startTime, let d = Calendar.current.date(bySettingHour:Int(s.prefix(2)) ?? 0, minute:Int(s.suffix(2)) ?? 0, second:0, of:Date()) else { return nil }
        return d.formatted(date:.omitted, time:.shortened)
    }
    var scheduleLabel: String {
        if let goal = weeklyGoal { return "\(goal) day\(goal == 1 ? "" : "s") a week" }
        switch Set(days) { case Set(0...6): return "Every day"; case [1,2,3,4,5]: return "Weekdays"; case [0,6]: return "Weekends"
        default: return Day.order.filter(days.contains).map { Calendar.current.shortWeekdaySymbols[$0] }.joined(separator:", ") }
    }
    func due(_ date: Date) -> Bool {
        let key = Day.key(date)
        return key >= createdAt && (archivedAt == nil || key < archivedAt!) && (weeklyGoal != nil || days.contains(Calendar.current.component(.weekday, from: date) - 1))
    }
}
struct FocusTimer: Codable {
    var id: String
    var day: String
    var durationMs: Double
    var remainingMs: Double
    var endsAt: Double?
    var status: String
    var logged = false
    var sessionId: String?
    var startedAt: Double?
    /// Active focus so far; paused time is excluded because pausing moves the deadline.
    func focused(at now: Date = Date()) -> Double { max(0, durationMs - remaining(at: now)) }
    var canLog: Bool { status == "finished" && !logged && focused() >= 60000 }
    var focusedMinutes: Int { max(1, Int((focused() / 60000).rounded())) }
    func remaining(at now: Date = Date()) -> Double {
        status == "running" ? min(durationMs, max(0, (endsAt ?? now.timeIntervalSince1970 * 1000) - now.timeIntervalSince1970 * 1000)) : remainingMs
    }
}
struct Session: Codable, Identifiable {
    var sessionId: String
    var habitId: String
    var day: String
    var startedAt: Double?
    var endedAt: Double
    var durationMs: Double
    var elapsedMs: Double
    var outcome: String
    var note: String
    var logged: Bool
    var id: String { sessionId }
}
struct AppData: Codable {
    var schema = 1
    var profile = Profile()
    var habits: [Habit] = []
    var records: [String:[String:Int]] = [:]
    var notes: [String:[String:String]] = [:]
    var timer: FocusTimer?
    var sessions: [Session] = []
    var onboarded = false
    var remindersEnabled = false
    // Native-only extras; the web tracker ignores them.
    var completedAt: [String:[String:Double]] = [:]   // day → habit → ms when the target was reached
    var prefs = Preferences()
    var updatedAt: Double = 0                          // ms; newest copy wins in iCloud sync
    enum CodingKeys: String, CodingKey { case schema, profile, habits, records, notes, timer, sessions, onboarded, remindersEnabled, completedAt, prefs, updatedAt }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        profile = try c.decodeIfPresent(Profile.self, forKey: .profile) ?? Profile()
        habits = try c.decode([Habit].self, forKey: .habits)
        records = try c.decodeIfPresent([String:[String:Int]].self, forKey: .records) ?? [:]
        notes = try c.decodeIfPresent([String:[String:String]].self, forKey: .notes) ?? [:]
        timer = try c.decodeIfPresent(FocusTimer.self, forKey: .timer)
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? true
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? false
        completedAt = try c.value(.completedAt, [:]); prefs = try c.value(.prefs, Preferences()); updatedAt = try c.value(.updatedAt, 0)
    }
}
struct Preferences: Codable, Equatable {
    var leadMinutes = 10
    var defaultMinutes = 25
    var liveActivity = true
    var endSound = true
    var mondayFirst = true
    var appearance = "system"   // system | light | dark
    var iCloud = false
}
extension Preferences {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leadMinutes = try c.value(.leadMinutes, 10); defaultMinutes = try c.value(.defaultMinutes, 25); liveActivity = try c.value(.liveActivity, true)
        endSound = try c.value(.endSound, true); mondayFirst = try c.value(.mondayFirst, true); appearance = try c.value(.appearance, "system"); iCloud = try c.value(.iCloud, false)
    }
}
// Older or hand-edited backups may omit fields; fall back to defaults and let import validation judge the result.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: T) throws -> T { try decodeIfPresent(T.self, forKey: key) ?? fallback }
}
extension Profile {
    init(from decoder: Decoder) throws { name = try decoder.container(keyedBy: CodingKeys.self).value(.name, "") }
}
extension Habit {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        category = try c.value(.category, category); icon = try c.value(.icon, icon); color = try c.value(.color, color)
        type = try c.value(.type, type); target = try c.value(.target, target); unit = try c.value(.unit, unit); days = try c.value(.days, days)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        archivedAt = try c.decodeIfPresent(String.self, forKey: .archivedAt); weeklyGoal = try c.decodeIfPresent(Int.self, forKey: .weeklyGoal); startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        reminder = try c.decodeIfPresent(Bool.self, forKey: .reminder)
    }
}
extension FocusTimer {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); day = try c.decode(String.self, forKey: .day)
        durationMs = try c.decode(Double.self, forKey: .durationMs); remainingMs = try c.decode(Double.self, forKey: .remainingMs)
        endsAt = try c.decodeIfPresent(Double.self, forKey: .endsAt); status = try c.decode(String.self, forKey: .status); logged = try c.value(.logged, false)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId); startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
    }
}
extension Session {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId); habitId = try c.decode(String.self, forKey: .habitId); day = try c.decode(String.self, forKey: .day)
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt); endedAt = try c.decode(Double.self, forKey: .endedAt)
        durationMs = try c.decode(Double.self, forKey: .durationMs); elapsedMs = try c.decode(Double.self, forKey: .elapsedMs)
        outcome = try c.decode(String.self, forKey: .outcome); note = try c.value(.note, ""); logged = try c.value(.logged, false)
    }
}
enum Day {
    private static let formatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.calendar = Calendar(identifier:.gregorian); f.timeZone = .autoupdatingCurrent; f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f }()
    static func key(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date? { guard let d = formatter.date(from:key), self.key(d) == key else { return nil }; return d }
    /// Set from Preferences; weekly goals reset on this day.
    static var mondayFirst = true
    /// Weekday indices (0 = Sunday) in display order.
    static var order: [Int] { mondayFirst ? [1,2,3,4,5,6,0] : [0,1,2,3,4,5,6] }
    static func week(_ date: Date) -> [Date] { let cal = Calendar.current; let weekday = cal.component(.weekday, from:date); let offset = mondayFirst ? (weekday + 5) % 7 : weekday - 1; let start = cal.date(byAdding:.day,value:-offset,to:cal.startOfDay(for:date))!; return (0..<7).compactMap { cal.date(byAdding:.day,value:$0,to:start) } }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
// Design tokens from the Daymark canvas (light / dark).
enum Palette {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        func ui(_ v: UInt32) -> UIColor { UIColor(red:CGFloat(v >> 16 & 0xFF)/255, green:CGFloat(v >> 8 & 0xFF)/255, blue:CGFloat(v & 0xFF)/255, alpha:1) }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    static let background = adaptive(0xF7F8F5, 0x101A1A)
    static let grouped = adaptive(0xF2F4F1, 0x101A1A)
    static let surface = adaptive(0xFFFFFF, 0x1B2826)
    static let text = adaptive(0x182522, 0xEEF2EF)
    static let secondary = adaptive(0x64736E, 0xA3B0AB)
    static let teal = adaptive(0x0A6E66, 0x4FB8AE)
    static let indigo = adaptive(0x5759C4, 0x9B9DF0)
    static let coral = adaptive(0xCC4D38, 0xF0866F)
    static let warning = adaptive(0xB8860B, 0xF0C36D)
    static let track = adaptive(0xE6EAE6, 0x2B3A37)
    static let ring = adaptive(0xC9D1CC, 0x3A4A46)
    static let chip = adaptive(0xF0F2EF, 0x263432)
    static let tealTint = adaptive(0xE3F1EF, 0x1F3A37)
    static let indigoTint = adaptive(0xECECF9, 0x2A2B4F)
    static let coralTint = adaptive(0xF9E8E4, 0x45271F)
    /// Text on teal/indigo fills: white in light mode, background in dark.
    static let onAccent = adaptive(0xFFFFFF, 0x101A1A)
}
