import SwiftUI

struct ProgressTab: View {
    @EnvironmentObject var store: HabitStore
    var body: some View {
        let days = (0..<7).reversed().compactMap { Calendar.current.date(byAdding:.day, value:-$0, to:Date()) }
        let stats = days.map { d -> (Date, Int, Int) in let due = store.dailyDue(d); return (d, due.filter { store.complete($0, d) }.count, due.count) }
        let scored = stats.filter { $0.2 > 0 }
        let avg = scored.isEmpty ? 0 : Int((scored.map { Double($0.1) / Double($0.2) }.reduce(0, +) / Double(scored.count) * 100).rounded())
        let active = store.data.habits.filter { $0.archivedAt == nil }
        let daily = active.filter { $0.weeklyGoal == nil }
        let weekly = active.filter { $0.weeklyGoal != nil }
        let best = daily.map { ($0, store.streak($0)) }.max { $0.1 < $1.1 }
        let week = store.weekSessions()
        let focusMs = week.reduce(0) { $0 + $1.elapsedMs }
        ScrollView {
            VStack(alignment:.leading, spacing:12) {
                if active.isEmpty {
                    ContentUnavailableView("Nothing to show yet", systemImage:"chart.bar", description:Text("Add a habit and check in. Your week shows up here."))
                } else {
                    VStack(alignment:.leading, spacing:14) {
                        HStack(alignment:.firstTextBaseline) { Text("Daily completion").font(.headline); Spacer(); Text("Last 7 days · avg \(avg)%").font(.footnote).foregroundStyle(Palette.secondary) }
                        HStack(alignment:.bottom, spacing:8) {
                            ForEach(stats, id:\.0) { d, done, due in
                                let today = Day.key(d) == Day.key(Date())
                                VStack(spacing:6) {
                                    RoundedRectangle(cornerRadius:8).fill(Palette.track).frame(height:96)
                                        .overlay(alignment:.bottom) { RoundedRectangle(cornerRadius:8).fill(Palette.teal).frame(height:due == 0 ? 0 : 96 * CGFloat(done) / CGFloat(due)) }
                                        .padding(today ? 2 : 0).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(today ? Palette.teal : .clear, lineWidth:2))
                                    Text(due == 0 ? "–" : "\(done)/\(due)").font(.caption2.weight(.semibold)).monospacedDigit()
                                    Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(today ? Palette.teal : Palette.secondary)
                                }.frame(maxWidth:.infinity)
                                    .accessibilityElement(children:.ignore).accessibilityLabel(d.formatted(.dateTime.weekday(.wide)) + (due == 0 ? ": rest day" : ": \(done) of \(due) done"))
                            }
                        }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        Text("Daily habits only. Rest days don't break anything.").font(.footnote).foregroundStyle(Palette.secondary)
                    }.card(16)
                    HStack(spacing:12) {
                        stat("Current streak", best.map { "\($0.1)" } ?? "0", unit:"days", detail:best.map { $0.0.name } ?? "Daily habits only", color:Palette.text)
                        stat("Focus this week", hoursMinutes(focusMs), unit:nil, detail:week.isEmpty ? "No sessions yet" : "\(week.count) session\(week.count == 1 ? "" : "s") · \(Int(focusMs / Double(week.count) / 60000)) min avg", color:Palette.indigo)
                    }
                    if !weekly.isEmpty {
                        VStack(alignment:.leading, spacing:10) {
                            HStack(alignment:.firstTextBaseline) { Text("Flexible weekly goals").font(.headline); Spacer(); Text("Resets " + (Day.mondayFirst ? "Monday" : "Sunday")).font(.footnote).foregroundStyle(Palette.secondary) }
                            ForEach(weekly) { h in
                                let done = store.weekly(h), goal = h.weeklyGoal ?? 1
                                HStack(spacing:10) {
                                    IconWell(habit:h, size:32)
                                    Text(h.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer(minLength:4)
                                    HStack(spacing:4) { ForEach(0..<goal, id:\.self) { i in Capsule().fill(i < done ? h.tint : Palette.track).frame(width:goal > 5 ? 14 : 22, height:8) } }.accessibilityHidden(true)
                                    Text("\(done) of \(goal)").font(.footnote.weight(.semibold)).monospacedDigit().frame(minWidth:44, alignment:.trailing)
                                }.accessibilityElement(children:.combine)
                            }
                        }.card(16)
                    }
                    if !daily.isEmpty {
                        VStack(alignment:.leading, spacing:12) {
                            HStack(alignment:.firstTextBaseline) { Text("Consistency").font(.headline); Spacer(); Text("Last 30 days").font(.footnote).foregroundStyle(Palette.secondary) }
                            ForEach(daily) { h in
                                let c = store.consistency(h)
                                HStack(spacing:10) {
                                    IconWell(habit:h, size:32)
                                    Text(h.name).font(.subheadline.weight(.medium)).lineLimit(1).frame(maxWidth:120, alignment:.leading)
                                    Rail(value:c.due == 0 ? 0 : Double(c.done) / Double(c.due), color:h.tint, height:6)
                                    Text("\(c.done) / \(c.due)").font(.footnote.weight(.semibold)).monospacedDigit().frame(minWidth:52, alignment:.trailing)
                                }.accessibilityElement(children:.combine)
                            }
                        }.card(16)
                    }
                }
            }.padding(.horizontal,20).padding(.bottom,20)
        }
        .background(Palette.background)
        .safeAreaInset(edge:.top) { ScreenHeader(title:"Progress") { Text("Week of " + (Day.week(Date()).first ?? Date()).formatted(.dateTime.month(.abbreviated).day())).font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondary) } }
        .toolbar(.hidden, for:.navigationBar)
    }
    func stat(_ title: String, _ value: String, unit: String?, detail: String, color: Color) -> some View {
        VStack(alignment:.leading, spacing:6) {
            Text(title).font(.footnote).foregroundStyle(Palette.secondary)
            (Text(value).font(.title.bold()).foregroundStyle(color) + Text(unit.map { " " + $0 } ?? "").font(.subheadline.weight(.medium)).foregroundStyle(Palette.secondary))
            Text(detail).font(.footnote).foregroundStyle(Palette.secondary).lineLimit(1)
        }.frame(maxWidth:.infinity, alignment:.leading).card(16).accessibilityElement(children:.combine)
    }
}

struct SessionsView: View {
    @EnvironmentObject var store: HabitStore
    @State private var selected: Session?
    var body: some View {
        let byDay = Dictionary(grouping:store.data.sessions, by:\.day).sorted { $0.key > $1.key }
        List {
            if byDay.isEmpty {
                ContentUnavailableView("Time well spent", systemImage:"timer", description:Text("Start a focus session from any habit. Your sessions will appear here.")).listRowBackground(Color.clear)
            }
            ForEach(byDay, id:\.key) { day, sessions in
                Section {
                    ForEach(sessions.sorted { $0.endedAt > $1.endedAt }) { s in
                        Button { selected = s } label: { row(s) }.buttonStyle(.plain)
                    }
                } header: {
                    HStack { Text(dayLabel(day)); Spacer(); Text(hoursMinutes(sessions.reduce(0) { $0 + $1.elapsedMs })).textCase(nil) }
                }
            }
            if !byDay.isEmpty {
                Text("Active focus only. Unlogged sessions never change a habit.").font(.caption).foregroundStyle(Palette.secondary).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden).background(Palette.background)
        .safeAreaInset(edge:.top) { ScreenHeader(title:"Sessions") { Text(hoursMinutes(store.weekSessions().reduce(0) { $0 + $1.elapsedMs }) + " this week").font(.footnote.weight(.semibold)).foregroundStyle(Palette.indigo) } }
        .toolbar(.hidden, for:.navigationBar)
        .sheet(item:$selected) { s in
            if let h = store.data.habits.first(where:{ $0.id == s.habitId }) { NoteEditor(habit:h, date:Day.date(s.day) ?? Date(), sessionId:s.id) }
        }
    }
    func row(_ s: Session) -> some View {
        let h = store.data.habits.first { $0.id == s.habitId }
        let outcome = ["stopped":"stopped early", "restarted":"restarted", "replaced":"replaced"][s.outcome] ?? (s.logged && h?.isMinutes == false ? "habit completed" : nil)
        return HStack(spacing:12) {
            if let h { IconWell(habit:h) }
            VStack(alignment:.leading, spacing:2) {
                HStack(spacing:6) {
                    Text(h?.name ?? "Habit").font(.headline)
                    if !s.note.isEmpty { Image(systemName:"note.text").font(.caption).foregroundStyle(Palette.secondary).accessibilityLabel("Has a note") }
                }
                Text(([sessionTimes(s)] + [outcome].compactMap { $0 }).joined(separator:" · ")).font(.footnote).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength:8)
            VStack(alignment:.trailing, spacing:2) {
                Text("\(Int(s.elapsedMs / 60000)) min").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(s.logged ? Palette.text : Palette.secondary)
                Label(s.logged ? "Logged" : "Not logged", systemImage:s.logged ? "checkmark.circle.fill" : "minus.circle").font(.caption.weight(.semibold)).foregroundStyle(s.logged ? Palette.teal : Palette.secondary)
            }
        }.frame(minHeight:44).contentShape(Rectangle())
    }
    func dayLabel(_ key: String) -> String {
        guard let d = Day.date(key) else { return key }
        return (key == Day.key(Date()) ? "Today · " : "") + d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
