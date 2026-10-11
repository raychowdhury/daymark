import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: HabitStore
    @State private var date = Date()
    @State private var settings = false
    @State private var editor = false
    @State private var suggestions = false
    @State private var picking = false
    @State private var focusFull = false
    var isToday: Bool { Day.key(date) == Day.key(Date()) }
    var habits: [Habit] { store.data.habits.filter { $0.due(date) } }
    var greeting: String {
        let part = "Good " + dayPart()
        return store.data.profile.name.isEmpty ? part : "\(part), \(store.data.profile.name)"
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:16) {
                header
                weekStrip
                summary
                if habits.isEmpty { empty } else {
                    ForEach(habits) { h in HabitCard(habit:h, date:date, openFocus:{ focusFull = true }) }
                    let weekly = habits.filter { $0.weeklyGoal != nil }
                    if !weekly.isEmpty && !store.dailyDue(date).isEmpty {
                        Text(weekly.count == 1 ? "\(weekly[0].name) is a weekly goal, not part of today's total." : "Weekly goals aren't part of today's total.").font(.footnote).foregroundStyle(Palette.secondary).frame(maxWidth:.infinity)
                    }
                }
            }.padding(.horizontal,20).padding(.bottom,20)
        }
        .background(Palette.background)
        .toolbar(.hidden, for:.navigationBar)
        .safeAreaInset(edge:.bottom) { if store.data.timer != nil { SessionBar { focusFull = true }.padding(.horizontal,16).padding(.bottom,8) } }
        .sheet(isPresented:$settings) { SettingsView() }
        .sheet(isPresented:$editor) { HabitEditor() }
        .sheet(isPresented:$suggestions) { NavigationStack { FirstHabitView { store.finishOnboarding(adding:$0) } } }
        .sheet(isPresented:$picking) { EarlierCheckIn(date:$date) }
        .fullScreenCover(isPresented:$focusFull) { FocusScreen() }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.significantTimeChangeNotification)) { _ in date = Date() }
    }
    var header: some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading, spacing:2) {
                Caps(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                Text(isToday ? greeting : "Checking in").font(.title.bold())
            }
            Spacer()
            Button { settings = true } label: {
                Image(systemName:"gearshape").font(.title3).foregroundStyle(Palette.text).frame(width:44, height:44).background(Palette.surface, in:Circle()).shadow(color:.black.opacity(0.08), radius:1, y:1)
            }.accessibilityLabel("Settings")
        }.padding(.top,8)
    }
    var weekStrip: some View {
        HStack(spacing:8) {
            HStack(spacing:4) {
                ForEach(Day.week(date), id:\.self) { day in
                    let selected = Day.key(day) == Day.key(date)
                    let today = Day.key(day) == Day.key(Date())
                    let future = Calendar.current.startOfDay(for:day) > Calendar.current.startOfDay(for:Date())
                    let state = store.dayState(day)
                    Button { date = day } label: {
                        VStack(spacing:6) {
                            Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(selected ? Palette.teal : Palette.secondary)
                            Text(day.formatted(.dateTime.day())).font(.caption.weight(.semibold))
                                .foregroundStyle(state == .full ? Palette.onAccent : today || selected ? Palette.teal : Palette.text)
                                .frame(width:28, height:28)
                                .background(state == .full ? Palette.teal : .clear, in:Circle())
                                .overlay(Circle().strokeBorder(state == .none && !(today || selected) ? Palette.ring : Palette.teal, style:StrokeStyle(lineWidth:2, dash:state == .partial ? [3, 2.5] : [])))
                        }.frame(maxWidth:.infinity).padding(.vertical,6).background(selected ? Palette.surface : .clear, in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(.plain).disabled(future).opacity(future ? 0.4 : 1)
                        .accessibilityLabel(day.formatted(date:.complete, time:.omitted) + (state == .full ? ", all done" : state == .partial ? ", partly done" : ""))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Button { picking = true } label: {
                Image(systemName:"calendar").font(.title3).foregroundStyle(Palette.teal).frame(width:44, height:56).background(Palette.surface, in:RoundedRectangle(cornerRadius:12))
            }.accessibilityLabel("Pick an earlier date")
        }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    @ViewBuilder var summary: some View {
        let daily = store.dailyDue(date)
        let done = daily.filter { store.complete($0, date) }.count
        let weekly = store.data.habits.filter { $0.weeklyGoal != nil && $0.due(date) }
        let weeklyLine = weekly.first.map { "\($0.name) \(store.weekly($0, date)) of \($0.weeklyGoal!) days" }
        if !daily.isEmpty && done == daily.count {
            HStack(spacing:14) {
                Image(systemName:"checkmark").font(.headline).frame(width:44, height:44).background(.white.opacity(0.18), in:Circle())
                VStack(alignment:.leading, spacing:2) {
                    Text(daily.count == 1 ? "Your daily habit is done" : "All \(daily.count) daily habits done").font(.headline)
                    if let weeklyLine { Text("Weekly · " + weeklyLine).font(.footnote).opacity(0.9) }
                }
                Spacer(minLength:0)
            }.foregroundStyle(Palette.onAccent).padding(16).background(Palette.teal, in:RoundedRectangle(cornerRadius:16))
                .accessibilityElement(children:.combine)
        } else {
            VStack(alignment:.leading, spacing:10) {
                HStack {
                    Text(isToday ? "Today" : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(daily.isEmpty ? (store.data.habits.isEmpty ? "No habits yet" : "No daily habits") : "\(done) of \(daily.count) done").font(.subheadline.weight(.semibold)).foregroundStyle(daily.isEmpty ? Palette.secondary : Palette.teal)
                }
                Rail(value:daily.isEmpty ? 0 : Double(done) / Double(daily.count), color:Palette.teal, height:6)
                if let weeklyLine { (Text("Weekly · ") + Text(weeklyLine).foregroundStyle(Palette.text).fontWeight(.medium)).font(.caption).foregroundStyle(Palette.secondary) }
            }.card(16).accessibilityElement(children:.combine)
        }
    }
    @ViewBuilder var empty: some View {
        let restDay = store.data.habits.contains { $0.archivedAt == nil }
        VStack(spacing:18) {
            DayMark(size:84, fill:Palette.tealTint, bar:Palette.teal, opacities:[0.35, 0.25, 0.15])
            VStack(spacing:6) {
                Text(restDay ? "A rest day" : "A clean slate").font(.title3.bold())
                Text(restDay ? "Nothing is scheduled for this day. Rest days never break a streak." : "Add a habit and it shows up here, ready to check off.").font(.subheadline).foregroundStyle(Palette.secondary)
            }.multilineTextAlignment(.center)
            if !restDay {
                Button("Add a habit", systemImage:"plus") { editor = true }.buttonStyle(BigButton(height:48)).frame(maxWidth:220)
                Button("Browse suggestions") { suggestions = true }.font(.subheadline.weight(.medium)).foregroundStyle(Palette.teal).frame(minHeight:44)
            }
        }.padding(.horizontal,20).padding(.vertical,40).frame(maxWidth:.infinity)
    }
}

struct HabitCard: View {
    @EnvironmentObject var store: HabitStore
    let habit: Habit
    let date: Date
    let openFocus: () -> Void
    @State private var notes = false
    @State private var focusSetup = false
    @State private var editing = false
    @State private var started = false
    var isToday: Bool { Day.key(date) == Day.key(Date()) }
    var done: Bool { store.complete(habit, date) }
    var amount: Int { store.amount(habit, date) }
    var meta: String {
        var parts = [habit.category]
        if let goal = habit.weeklyGoal { parts.append("\(store.weekly(habit, date)) of \(goal) days this week") }
        else if habit.isMinutes { parts.append("\(amount) of \(habit.target) min") }
        else if habit.type == "count" { parts.append("\(amount) of \(habit.target) \(habit.unit)") }
        if let start = habit.startLabel, !done { parts.append(start) }
        if done && habit.type == "check" && habit.weeklyGoal == nil { parts.append(store.doneAt(habit, date).map { "Done " + $0.formatted(date:.omitted, time:.shortened) } ?? "Done") }
        if done && habit.type == "count" { parts.append("Complete") }
        return parts.joined(separator:" · ")
    }
    var body: some View {
        VStack(alignment:.leading, spacing:12) {
            HStack(spacing:12) {
                IconWell(habit:habit)
                VStack(alignment:.leading, spacing:2) {
                    HStack(spacing:6) {
                        Text(habit.name).font(.headline)
                        if !store.note(habit, date).isEmpty { Image(systemName:"note.text").font(.caption).foregroundStyle(Palette.secondary).accessibilityLabel("Has a note") }
                    }
                    Text(meta).font(.footnote).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength:8)
                control
            }
            if habit.type == "count" { Rail(value:Double(amount) / Double(habit.target), color:habit.tint) }
            if habit.isMinutes { HStack(spacing:8) {
                if isToday, let start = habit.startTime, !done {
                    TimelineView(.periodic(from:Date(), by:30)) { context in
                        let target = Calendar.current.date(bySettingHour:Int(start.prefix(2)) ?? 0, minute:Int(start.suffix(2)) ?? 0, second:0, of:context.date) ?? context.date
                        if target > context.date { Label("Starts in " + countdown(target.timeIntervalSince(context.date)), systemImage:"clock").font(.footnote.weight(.medium)).foregroundStyle(Palette.indigo) }
                    }
                }
                Spacer(minLength:0)
                Button(store.note(habit, date).isEmpty ? "Note" : "Notes") { notes = true }.buttonStyle(Pill())
                if isToday {
                    Button("Focus", systemImage:"play.fill", action:focus).buttonStyle(Pill(fill:Palette.indigo, text:Palette.onAccent))
                }
            } }
        }
        .card().opacity(done ? 0.72 : 1)
        .contextMenu {
            if habit.type == "count" {
                Button("Add one", systemImage:"plus") { store.setAmount(habit, amount + 1, date) }
                Button("Remove one", systemImage:"minus") { store.setAmount(habit, amount - 1, date) }.disabled(amount == 0)
            } else {
                Button(done ? "Mark not done" : "Mark done", systemImage:done ? "arrow.uturn.backward" : "checkmark") { toggle() }
            }
            Button(store.note(habit, date).isEmpty ? "Add note" : "View note", systemImage:"note.text") { notes = true }
            if isToday { Button("Focus", systemImage:"timer", action:focus) }
            Button("Edit habit", systemImage:"pencil") { editing = true }
        }
        .sheet(isPresented:$notes) { NoteEditor(habit:habit, date:date) }
        .sheet(isPresented:$focusSetup, onDismiss:{ if started { started = false; openFocus() } }) { FocusSetup(habit:habit) { started = true } }
        .sheet(isPresented:$editing) { HabitEditor(habit:habit) }
    }
    @ViewBuilder var control: some View {
        if habit.type == "check" {
            Button(action:toggle) {
                Image(systemName:"checkmark").font(.system(size:18, weight:.bold)).foregroundStyle(done ? Palette.onAccent : .clear)
                    .frame(width:44, height:44).background(done ? Palette.teal : Palette.surface, in:Circle())
                    .overlay(Circle().strokeBorder(done ? Palette.teal : Palette.ring, lineWidth:2))
            }.buttonStyle(.plain).accessibilityLabel(done ? "Mark \(habit.name) not done" : "Complete \(habit.name)")
        } else if done {
            Text(habit.isMinutes ? "\(amount) min" : "\(amount) / \(habit.target)").font(.subheadline.weight(.semibold)).foregroundStyle(habit.tint)
                .padding(.horizontal,14).frame(minHeight:44).background(habit.wash, in:Capsule())
        } else if !habit.isMinutes {
            Button("+1") { store.setAmount(habit, amount + 1, date) }.font(.body.weight(.semibold)).foregroundStyle(Palette.onAccent)
                .frame(minWidth:44, minHeight:44).padding(.horizontal,6).background(Palette.teal, in:Capsule())
                .accessibilityLabel("Add one to \(habit.name)").accessibilityValue("\(amount) of \(habit.target) \(habit.unit)")
        }
    }
    func toggle() { store.setAmount(habit, done ? 0 : habit.target, date) }
    func focus() { if store.data.timer?.id == habit.id { openFocus() } else { focusSetup = true } }
    func countdown(_ seconds: TimeInterval) -> String { let m = Int(seconds / 60) + 1; return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min" }
}

/// The compact active-session bar above the tab bar.
struct SessionBar: View {
    @EnvironmentObject var store: HabitStore
    let open: () -> Void
    var body: some View {
        if let t = store.data.timer, let h = store.data.habits.first(where:{ $0.id == t.id }) {
            let status = t.status == "finished" ? (t.logged ? "Logged" : t.remainingMs > 0 ? "Stopped" : "Completed") : t.status.capitalized
            HStack(spacing:12) {
                Circle().fill(Palette.onAccent).frame(width:8, height:8).accessibilityHidden(true)
                VStack(alignment:.leading, spacing:1) {
                    Text("\(h.name) · \(status)").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(t.status == "finished" ? (t.canLog ? "Tap to log or dismiss" : "Tap to close") : "\(timerString(t.remaining())) left").font(.caption).monospacedDigit().opacity(0.85)
                }
                Spacer(minLength:4)
                if t.status != "finished" {
                    Button(t.status == "running" ? "Pause" : "Resume", systemImage:t.status == "running" ? "pause.fill" : "play.fill") { store.pauseResume() }
                        .font(.subheadline.weight(.semibold)).padding(.horizontal,14).frame(height:40).background(Palette.onAccent.opacity(0.16), in:RoundedRectangle(cornerRadius:12))
                }
            }
            .foregroundStyle(Palette.onAccent).padding(.leading,16).padding(.trailing,10).frame(minHeight:56)
            .background(Palette.indigo, in:RoundedRectangle(cornerRadius:18)).shadow(color:Palette.indigo.opacity(0.28), radius:10, y:8)
            .contentShape(Rectangle()).onTapGesture(perform:open)
            .accessibilityElement(children:.combine).accessibilityAddTraits(.isButton).accessibilityHint("Opens the focus session").accessibilityAction(named:"Open", open)
        }
    }
}

struct EarlierCheckIn: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.dismiss) var dismiss
    @Binding var date: Date
    @State private var pick = Date()
    @State private var month = Date()
    let cal = Calendar.current
    var days: [Date?] {
        let first = cal.date(from:cal.dateComponents([.year, .month], from:month))!
        let blanks = Day.order.firstIndex(of:cal.component(.weekday, from:first) - 1) ?? 0
        return Array(repeating:nil, count:blanks) + cal.range(of:.day, in:.month, for:first)!.map { cal.date(byAdding:.day, value:$0 - 1, to:first) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading, spacing:16) {
                    Text("Pick a past day to log it.").font(.subheadline).foregroundStyle(Palette.secondary)
                    HStack {
                        monthButton("chevron.left", "Previous month", -1)
                        Spacer(); Text(month.formatted(.dateTime.month(.wide).year())).font(.headline); Spacer()
                        monthButton("chevron.right", "Next month", 1).disabled(cal.isDate(month, equalTo:Date(), toGranularity:.month)).opacity(cal.isDate(month, equalTo:Date(), toGranularity:.month) ? 0.4 : 1)
                    }
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(), spacing:6), count:7), spacing:6) {
                        ForEach(Day.order, id:\.self) { Text(cal.veryShortWeekdaySymbols[$0]).font(.caption2.weight(.semibold)).foregroundStyle(Palette.secondary) }
                        ForEach(Array(days.enumerated()), id:\.offset) { _, day in
                            if let day { cell(day) } else { Color.clear.frame(height:44) }
                        }
                    }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    HStack(spacing:14) {
                        Label { Text("All done") } icon: { Circle().fill(Palette.teal).frame(width:6, height:6) }
                        Label { Text("Partly") } icon: { Circle().fill(Palette.ring).frame(width:6, height:6) }
                    }.font(.caption).foregroundStyle(Palette.secondary)
                    Button(Day.key(pick) == Day.key(Date()) ? "Back to today" : "Check in for " + pick.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) { date = pick; dismiss() }.buttonStyle(BigButton())
                }.padding(20)
            }
            .background(Palette.surface)
            .navigationTitle("Earlier check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(Palette.teal)
        .onAppear { pick = date; month = date }
        .presentationDetents([.large])
    }
    func cell(_ day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs:pick), today = cal.isDateInToday(day)
        let future = cal.startOfDay(for:day) > cal.startOfDay(for:Date())
        let state = future ? HabitStore.DayState.none : store.dayState(day)
        return Button { pick = day } label: {
            VStack(spacing:3) {
                Text(day.formatted(.dateTime.day())).font(.body.weight(selected || today ? .semibold : .medium))
                Circle().fill(selected && state != .none ? Palette.onAccent : state == .full ? Palette.teal : state == .partial ? Palette.ring : .clear).frame(width:5, height:5)
            }
            .frame(maxWidth:.infinity, minHeight:44)
            .foregroundStyle(selected ? Palette.onAccent : future ? Palette.ring : today ? Palette.teal : Palette.text)
            .background(selected ? Palette.teal : .clear, in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(today && !selected ? Palette.teal : .clear, lineWidth:2))
        }.buttonStyle(.plain).disabled(future)
            .accessibilityLabel(day.formatted(date:.complete, time:.omitted) + (state == .full ? ", all done" : state == .partial ? ", partly done" : ""))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    func monthButton(_ symbol: String, _ label: String, _ step: Int) -> some View {
        Button { month = cal.date(byAdding:.month, value:step, to:month) ?? month } label: {
            Image(systemName:symbol).font(.headline).foregroundStyle(Palette.text).frame(width:44, height:44).background(Palette.chip, in:Circle())
        }.accessibilityLabel(label)
    }
}
