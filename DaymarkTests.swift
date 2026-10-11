import XCTest
@testable import Daymark

final class DaymarkTests: XCTestCase {
    func testDeadlineSurvivesInactiveApp() {
        let now = Date(timeIntervalSince1970:1000)
        let t = FocusTimer(id:"habit",day:"2026-10-11",durationMs:60000,remainingMs:60000,endsAt:1060000,status:"running")
        XCTAssertEqual(t.remaining(at:now),60000)
        XCTAssertEqual(t.remaining(at:now.addingTimeInterval(30)),30000)
        XCTAssertEqual(t.remaining(at:now.addingTimeInterval(90)),0)
    }
    func testPausedTimeDoesNotAdvance() {
        let t = FocusTimer(id:"habit",day:"2026-10-11",durationMs:60000,remainingMs:30000,status:"paused")
        XCTAssertEqual(t.remaining(at:Date(timeIntervalSince1970:90000)),30000)
    }
    func testMondayWeekBoundary() throws {
        let monday = try XCTUnwrap(Day.date("2026-10-12"))
        let sunday = try XCTUnwrap(Day.date("2026-10-11"))
        XCTAssertEqual(Day.key(Day.week(monday)[0]),"2026-10-12")
        XCTAssertEqual(Day.key(Day.week(sunday)[0]),"2026-10-05")
    }
    func testArchivePreservesPastEligibility() throws {
        let h = Habit(name:"Read",createdAt:"2026-10-01",archivedAt:"2026-10-11")
        XCTAssertTrue(h.due(try XCTUnwrap(Day.date("2026-10-10"))))
        XCTAssertFalse(h.due(try XCTUnwrap(Day.date("2026-10-11"))))
    }
    func testLegacyWebBackupDefaults() throws {
        let bytes = Data(#"{"schema":1,"habits":[{"id":"h-old","name":"Read","category":"Mind","icon":"book","color":"sage","type":"check","target":1,"unit":"times","days":[0,1,2,3,4,5,6],"createdAt":"2026-10-01"}],"records":{},"notes":{}}"#.utf8)
        let data = try JSONDecoder().decode(AppData.self,from:bytes)
        XCTAssertEqual(data.habits[0].id,"h-old")
        XCTAssertTrue(data.sessions.isEmpty)
        XCTAssertFalse(data.remindersEnabled)
        let restored = try JSONDecoder().decode(AppData.self,from:JSONEncoder().encode(data))
        XCTAssertEqual(restored.habits[0].name,"Read")
    }
    func testSparseBackupUsesDefaults() throws {
        let bytes = Data(#"{"schema":1,"profile":{},"habits":[{"id":"h","name":"Walk","createdAt":"2026-10-01"}],"timer":{"id":"h","day":"2026-10-11","durationMs":60000,"remainingMs":0,"status":"finished"},"sessions":[{"sessionId":"s","habitId":"h","day":"2026-10-11","endedAt":1,"durationMs":60000,"elapsedMs":60000,"outcome":"completed"}]}"#.utf8)
        let data = try JSONDecoder().decode(AppData.self,from:bytes)
        XCTAssertEqual(data.habits[0].days,[0,1,2,3,4,5,6])
        XCTAssertEqual(data.habits[0].type,"check")
        XCTAssertFalse(try XCTUnwrap(data.timer).logged)
        XCTAssertEqual(data.sessions[0].note,"")
        XCTAssertFalse(data.sessions[0].logged)
    }
    @MainActor func makeStore() -> HabitStore {
        let store = HabitStore(url:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json"))
        store.data.prefs.liveActivity = false   // no real Live Activities from tests
        return store
    }
    @MainActor func testCompletionTimeIsKeptOnlyWhileComplete() throws {
        let store = makeStore()
        let water = Habit(name:"Water", type:"count", target:2, unit:"glasses")
        store.upsert(water)
        store.setAmount(water, 1); XCTAssertNil(store.doneAt(water))
        store.setAmount(water, 2); let first = try XCTUnwrap(store.doneAt(water))
        store.setAmount(water, 3); XCTAssertEqual(store.doneAt(water), first)   // going past the target keeps the original time
        store.setAmount(water, 1); XCTAssertNil(store.doneAt(water))
    }
    @MainActor func testCSVQuotesAndCompletion() {
        let store = makeStore()
        let h = Habit(name:"Read, slowly")
        store.upsert(h); store.setAmount(h, 1); store.setNote(h, "Said \"hi\"")
        let csv = String(decoding:store.csv(), as:UTF8.self).split(separator:"\n")
        XCTAssertEqual(csv.count, 2)
        XCTAssertTrue(csv[1].contains("\"Read, slowly\""))
        XCTAssertTrue(csv[1].contains(",yes,"))
        XCTAssertTrue(csv[1].hasSuffix("\"Said \"\"hi\"\"\""))
    }
    func testSundayFirstWeek() throws {
        Day.mondayFirst = false; defer { Day.mondayFirst = true }
        XCTAssertEqual(Day.key(Day.week(try XCTUnwrap(Day.date("2026-10-11")))[0]), "2026-10-11")
        XCTAssertEqual(Day.key(Day.week(try XCTUnwrap(Day.date("2026-10-17")))[0]), "2026-10-11")
        XCTAssertEqual(Day.order.first, 0)
    }
    func testPreferencesDefaultWhenMissing() throws {
        let data = try JSONDecoder().decode(AppData.self, from:Data(#"{"schema":1,"habits":[],"prefs":{"appearance":"dark"}}"#.utf8))
        XCTAssertEqual(data.prefs.appearance, "dark")
        XCTAssertEqual(data.prefs.leadMinutes, 10)
        XCTAssertFalse(data.prefs.iCloud)
        XCTAssertTrue(data.completedAt.isEmpty)
    }
    @MainActor func testStoppedSessionLogsFocusedMinutesOnce() throws {
        let store = makeStore()
        let study = Habit(name:"Study", type:"count", target:50, unit:"minutes")
        store.upsert(study)
        store.start(study, minutes:25)
        store.data.timer?.endsAt = Date().timeIntervalSince1970 * 1000 + 12 * 60000   // 13 of 25 min focused
        store.finish("stopped")
        XCTAssertTrue(try XCTUnwrap(store.data.timer).canLog)
        store.logTimer(); store.logTimer()
        XCTAssertEqual(store.amount(study), 13)
        XCTAssertEqual(store.data.sessions.first?.outcome, "stopped")
        XCTAssertTrue(try XCTUnwrap(store.data.sessions.first).logged)
    }
    @MainActor func testReplaceCanLogThenStart() {
        let store = makeStore()
        let walk = Habit(name:"Walk"), read = Habit(name:"Read")
        store.upsert(walk); store.upsert(read)
        store.start(walk, minutes:10)
        store.data.timer?.endsAt = Date().timeIntervalSince1970 * 1000 + 4 * 60000
        store.start(read, minutes:15, logCurrent:true)
        XCTAssertTrue(store.complete(walk))
        XCTAssertEqual(store.data.timer?.id, read.id)
        XCTAssertEqual(store.data.sessions.first?.outcome, "replaced")
    }
    @MainActor func testUnderAMinuteCannotBeLogged() {
        let store = makeStore()
        let walk = Habit(name:"Walk")
        store.upsert(walk); store.start(walk, minutes:10); store.finish("stopped")
        XCTAssertFalse(store.data.timer!.canLog)
        store.logTimer()
        XCTAssertFalse(store.complete(walk))
    }
    @MainActor func testDayStateIgnoresWeeklyGoals() {
        let store = makeStore()
        let walk = Habit(name:"Walk", createdAt:"2026-01-01"), read = Habit(name:"Read", createdAt:"2026-01-01", weeklyGoal:3)
        let stretch = Habit(name:"Stretch", createdAt:"2026-01-01")
        store.upsert(walk); store.upsert(read); store.upsert(stretch)
        XCTAssertEqual(store.dayState(Date()), .none)
        store.setAmount(walk, 1)
        XCTAssertEqual(store.dayState(Date()), .partial)
        store.setAmount(stretch, 1)
        XCTAssertEqual(store.dayState(Date()), .full)
    }
    func testRejectsImpossibleDates() { XCTAssertNil(Day.date("2026-02-30")); XCTAssertNil(Day.date("2026-13-01")) }
}
