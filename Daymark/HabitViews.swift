import SwiftUI

struct HabitsView: View {
    @EnvironmentObject var store: HabitStore
    @State private var selected: Habit?
    @State private var adding: Habit?
    @State private var archive: Habit?
    var categories: [String] { ["Body", "Mind", "Life"] + Set(store.data.habits.map(\.category)).subtracting(["Body", "Mind", "Life"]).sorted() }
    var body: some View {
        let active = store.data.habits.filter { $0.archivedAt == nil }
        let archived = store.data.habits.filter { $0.archivedAt != nil }
        List {
            ForEach(categories, id:\.self) { cat in
                let rows = active.filter { $0.category == cat }
                if !rows.isEmpty || ["Body", "Mind", "Life"].contains(cat) {
                    Section(cat) {
                        ForEach(rows) { h in
                            Button { selected = h } label: { row(h) }.buttonStyle(.plain)
                                .swipeActions { Button("Archive") { archive = h }.tint(Palette.coral) }
                        }
                        if rows.isEmpty {
                            Button { adding = Habit(name:"", category:cat) } label: {
                                Label("Add a \(cat) habit", systemImage:"plus").font(.body.weight(.medium)).foregroundStyle(Palette.teal).frame(minHeight:44)
                            }
                        }
                    }
                }
            }
            if !archived.isEmpty {
                Section("Archived · \(archived.count)") {
                    ForEach(archived) { h in
                        HStack(spacing:12) {
                            IconWell(habit:h)
                            VStack(alignment:.leading, spacing:2) {
                                Text(h.name).font(.headline).foregroundStyle(Palette.secondary)
                                Text("Archived " + (h.archivedAt.flatMap(Day.date)?.formatted(.dateTime.month(.abbreviated).day()) ?? "") + " · history kept").font(.footnote).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Button("Restart") { store.restartArchived(h) }.buttonStyle(Pill(fill:Palette.tealTint, text:Palette.teal))
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(Palette.background)
        .safeAreaInset(edge:.top) {
            ScreenHeader(title:"Habits") {
                Button { adding = Habit(name:"") } label: { Image(systemName:"plus").font(.headline).foregroundStyle(Palette.onAccent).frame(width:44, height:44).background(Palette.teal, in:Circle()) }.accessibilityLabel("New habit")
            }
        }
        .toolbar(.hidden, for:.navigationBar)
        .sheet(item:$selected) { HabitEditor(habit:$0) }
        .sheet(item:$adding) { HabitEditor(draft:$0) }
        .confirmationDialog("Archive \(archive?.name ?? "this habit")?", isPresented:Binding(get:{ archive != nil }, set:{ if !$0 { archive = nil } }), titleVisibility:.visible) {
            Button("Archive", role:.destructive) { if let h = archive { store.archive(h) }; archive = nil }
        } message: { Text(archiveMessage(archive)) }
    }
    func row(_ h: Habit) -> some View {
        let streak = store.streak(h)
        let notes = store.data.notes.values.filter { $0[h.id]?.isEmpty == false }.count
        var parts = [h.type == "check" ? "Check off" : "Count · \(h.target) \(h.unit)", h.scheduleLabel]
        if let start = h.startLabel { parts.append(start) }
        if notes > 0 { parts.append("\(notes) note\(notes == 1 ? "" : "s")") }
        return HStack(spacing:12) {
            IconWell(habit:h)
            VStack(alignment:.leading, spacing:2) { Text(h.name).font(.headline); Text(parts.joined(separator:" · ")).font(.footnote).foregroundStyle(Palette.secondary) }
            Spacer(minLength:8)
            if streak >= 2 { Text("\(streak)-day streak").font(.footnote.weight(.medium)).foregroundStyle(Palette.teal) }
        }.frame(minHeight:44).contentShape(Rectangle())
    }
    func archiveMessage(_ h: Habit?) -> String {
        guard let h else { return "" }
        let checkIns = store.data.records.values.filter { ($0[h.id] ?? 0) > 0 }.count
        let notes = store.data.notes.values.filter { $0[h.id]?.isEmpty == false }.count
        return "\(checkIns) check-in\(checkIns == 1 ? "" : "s") and \(notes) note\(notes == 1 ? "" : "s") are kept. Restart any time."
    }
}

struct HabitEditor: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.dismiss) var dismiss
    @State var habit: Habit
    @State private var weekly: Bool
    @State private var scheduled: Bool
    @State private var time: Date
    @State private var confirmArchive = false
    let isNew: Bool
    init(habit: Habit? = nil, draft: Habit? = nil) {
        let h = habit ?? draft ?? Habit(name:"")
        isNew = habit == nil
        _habit = State(initialValue:h); _weekly = State(initialValue:h.weeklyGoal != nil); _scheduled = State(initialValue:h.startTime != nil)
        let pieces = (h.startTime ?? "09:00").split(separator:":").compactMap { Int($0) }
        _time = State(initialValue:Calendar.current.date(bySettingHour:pieces.first ?? 9, minute:pieces.last ?? 0, second:0, of:Date()) ?? Date())
    }
    var invalid: Bool { habit.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || habit.name.count > 200 || (!weekly && habit.days.isEmpty) || habit.target < 1 || habit.target > 99999 }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") { TextField("Habit name", text:$habit.name).multilineTextAlignment(.trailing) }
                    LabeledContent("Category") { segmented($habit.category, [("Body", "Body"), ("Mind", "Mind"), ("Life", "Life")]) }
                    LabeledContent("Icon & color") {
                        HStack(spacing:10) {
                            Menu {
                                Picker("Icon", selection:$habit.icon) { ForEach(["focus", "walk", "book", "water", "moon", "heart", "dumbbell", "leaf", "sun", "spark", "coffee"], id:\.self) { key in Label(key.capitalized, systemImage:Habit(name:"", icon:key).symbol).tag(key) } }
                            } label: { IconWell(habit:habit) }.accessibilityLabel("Choose icon")
                            ForEach([("sage", "Teal"), ("blue", "Indigo"), ("clay", "Coral")], id:\.0) { key, label in
                                let on = habit.color == key
                                Button { habit.color = key } label: {
                                    Circle().fill(Habit(name:"", color:key).tint).frame(width:28, height:28).padding(3).overlay(Circle().strokeBorder(on ? Palette.text : .clear, lineWidth:2)).frame(width:44, height:44)
                                }.buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                }
                Section {
                    LabeledContent("Type") { segmented($habit.type, [("check", "Check off"), ("count", "Count")]) }
                    if habit.type == "count" {
                        LabeledContent("Daily target") { TextField("Target", value:$habit.target, format:.number).multilineTextAlignment(.trailing).keyboardType(.numberPad) }
                        LabeledContent("Unit") { TextField("glasses, pages, minutes…", text:$habit.unit).multilineTextAlignment(.trailing) }
                    }
                } header: { Text("Tracking") } footer: { Text(habit.type == "count" ? "Complete at the daily target. Use “minutes” to log focus sessions." : "Done with one tap.") }
                Section {
                    LabeledContent("Repeat") { segmented($weekly, [(false, "Chosen days"), (true, "Days per week")]) }
                    if weekly {
                        Stepper("\(habit.weeklyGoal ?? 3) days a week", value:Binding(get:{ habit.weeklyGoal ?? 3 }, set:{ habit.weeklyGoal = $0 }), in:1...7)
                    } else {
                        HStack {
                            ForEach(Day.order, id:\.self) { day in
                                let on = habit.days.contains(day)
                                Button { if on { habit.days.removeAll { $0 == day } } else { habit.days.append(day) } } label: {
                                    Text(Calendar.current.veryShortWeekdaySymbols[day]).font(.subheadline.weight(.semibold)).frame(width:38, height:38)
                                        .foregroundStyle(on ? Palette.onAccent : Palette.text).background(on ? Palette.teal : Palette.chip, in:Circle())
                                }.buttonStyle(.plain).frame(maxWidth:.infinity)
                                    .accessibilityLabel(Calendar.current.weekdaySymbols[day]).accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    }
                } header: { Text("Frequency") } footer: {
                    Text(weekly ? "Any \(habit.weeklyGoal ?? 3) days. Resets \(Day.mondayFirst ? "Monday" : "Sunday"). Not part of the daily total." : habit.days.isEmpty ? "Choose at least one day." : "Shows on \(Set(habit.days).count) day\(Set(habit.days).count == 1 ? "" : "s") a week.")
                }
                Section {
                    Toggle("Scheduled start", isOn:$scheduled)
                    if scheduled { DatePicker("Time", selection:$time, displayedComponents:.hourAndMinute) }
                    Toggle("Reminder", isOn:Binding(get:{ scheduled && habit.reminder == true }, set:{ on in
                        habit.reminder = on
                        if on && !store.reminders { Task { await store.requestReminders(); if !store.reminders { habit.reminder = false } } }
                    })).disabled(!scheduled)
                } header: { Text("Schedule") } footer: { Text("Today shows “Starts in…” before this time. A reminder asks for notification permission.") }
                if !isNew && habit.archivedAt == nil {
                    Section { NavigationLink("Notes") { HabitNotesList(habit:habit) } }
                    Section {
                        Button("Archive this habit", systemImage:"archivebox", role:.destructive) { confirmArchive = true }
                    } header: { Text("Archive") } footer: { Text("Hides \(habit.name) from Today. History stays in Progress and Sessions.") }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden).background(Palette.grouped)
            .navigationTitle(isNew ? "New Habit" : "Edit Habit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save", action:save).fontWeight(.semibold).disabled(invalid) }
            }
            .confirmationDialog("Archive \(habit.name)?", isPresented:$confirmArchive, titleVisibility:.visible) {
                Button("Archive", role:.destructive) { store.archive(habit); dismiss() }
            } message: { Text("Its check-ins and notes are kept. Restart any time.") }
            .errorAlert(store)
        }
        .tint(Palette.teal)
    }
    func segmented<T: Hashable>(_ selection: Binding<T>, _ options: [(T, String)]) -> some View {
        Picker("", selection:selection) { ForEach(options, id:\.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth:220)
    }
    func save() {
        habit.name = habit.name.trimmingCharacters(in:.whitespacesAndNewlines)
        habit.weeklyGoal = weekly ? (habit.weeklyGoal ?? 3) : nil
        if habit.type == "check" { habit.target = 1 }
        let c = Calendar.current.dateComponents([.hour, .minute], from:time)
        habit.startTime = scheduled ? String(format:"%02d:%02d", c.hour ?? 9, c.minute ?? 0) : nil
        habit.reminder = scheduled && habit.reminder == true
        habit.days = Array(Set(habit.days)).sorted(); if weekly && habit.days.isEmpty { habit.days = Array(0...6) }
        store.upsert(habit); dismiss()
    }
}

/// One note per habit per day, or a note on a logged session.
struct NoteEditor: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.dismiss) var dismiss
    let habit: Habit
    let date: Date
    var sessionId: String?
    @State private var session = false
    @State private var text = ""
    @State private var saved = ""
    var stored: String { session ? store.data.sessions.first { $0.id == sessionId }?.note ?? "" : store.note(habit, date) }
    var dirty: Bool { text != saved }
    var body: some View {
        NavigationStack {
            VStack(alignment:.leading, spacing:12) {
                if sessionId != nil && store.data.sessions.contains(where:{ $0.id == sessionId }) {
                    Picker("Note belongs to", selection:$session) { Text("Habit · \(Day.key(date) == Day.key(Date()) ? "today" : date.formatted(.dateTime.month(.abbreviated).day()))").tag(false); Text("This session").tag(true) }.pickerStyle(.segmented)
                }
                HStack(spacing:12) {
                    IconWell(habit:habit, size:36)
                    VStack(alignment:.leading, spacing:1) { Text(habit.name).font(.subheadline.weight(.semibold)); Text(context).font(.footnote).foregroundStyle(Palette.secondary) }
                    Spacer()
                }.padding(10).background(Palette.background, in:RoundedRectangle(cornerRadius:14))
                TextEditor(text:$text).scrollContentBackground(.hidden).accessibilityLabel("Note")
                    .overlay(alignment:.topLeading) { if text.isEmpty { Text("What went well? What got in the way?").foregroundStyle(Palette.secondary).padding(.top,8).padding(.leading,5).allowsHitTesting(false) } }
                Divider()
                HStack {
                    if dirty { Text("Unsaved").foregroundStyle(Palette.secondary) } else if !saved.isEmpty { Label("Saved", systemImage:"checkmark").foregroundStyle(Palette.teal) }
                    Spacer()
                    Text("\(text.count.formatted()) / 2,000").monospacedDigit().foregroundStyle(text.count >= 1900 ? Palette.coral : Palette.secondary)
                }.font(.footnote)
            }
            .padding(16).background(Palette.surface)
            .navigationTitle(session ? "Session Note" : "Habit Note").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).disabled(!dirty) }
            }
        }
        .tint(Palette.teal)
        .onAppear { session = sessionId != nil && store.data.sessions.contains { $0.id == sessionId }; text = stored; saved = text }
        .onChange(of:session) { _, _ in text = stored; saved = text }
        .onChange(of:text) { _, value in if value.count > 2000 { text = String(value.prefix(2000)) } }
    }
    var context: String {
        if session, let s = store.data.sessions.first(where:{ $0.id == sessionId }) { return sessionTimes(s) + " · \(Int(s.elapsedMs / 60000)) min" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
    func save() {
        if session, let id = sessionId { store.setSessionNote(id, text) } else { store.setNote(habit, text, date) }
        saved = text; dismiss()
    }
}
func sessionTimes(_ s: Session) -> String {
    let end = Date(timeIntervalSince1970:s.endedAt / 1000).formatted(date:.omitted, time:.shortened)
    guard let started = s.startedAt else { return end }
    return Date(timeIntervalSince1970:started / 1000).formatted(date:.omitted, time:.shortened) + "–" + end
}

struct HabitNotesList: View {
    @EnvironmentObject var store: HabitStore
    let habit: Habit
    @State private var editing: Date?
    @State private var sessionNote: Session?
    var body: some View {
        let notes = store.data.notes.compactMap { day, entries in entries[habit.id].flatMap { $0.isEmpty ? nil : (day, $0) } }.sorted { $0.0 > $1.0 }
        let sessions = store.data.sessions.filter { $0.habitId == habit.id && !$0.note.isEmpty }.sorted { $0.endedAt > $1.endedAt }
        ScrollView {
            VStack(alignment:.leading, spacing:22) {
                VStack(alignment:.leading, spacing:10) {
                    Caps("Habit notes · \(notes.count)")
                    ForEach(notes, id:\.0) { day, body in
                        Button { editing = Day.date(day) } label: { noteCard(dayLabel(day), body) }.buttonStyle(.plain)
                    }
                    if notes.isEmpty { emptyCard("No habit notes yet", "Tap Note on a habit card in Today.") }
                }
                VStack(alignment:.leading, spacing:10) {
                    Caps("Session notes")
                    ForEach(sessions) { s in Button { sessionNote = s } label: { noteCard(dayLabel(s.day) + " · " + sessionTimes(s), s.note) }.buttonStyle(.plain) }
                    if sessions.isEmpty { emptyCard("No session notes yet", "Add one after logging a session. They show here and in Sessions.") }
                }
                Text("Up to 2,000 characters. Today marks habits that have a note.").font(.caption).foregroundStyle(Palette.secondary)
            }.padding(16)
        }
        .background(Palette.background)
        .navigationTitle("Notes").navigationBarTitleDisplayMode(.inline)
        .sheet(item:Binding(get:{ editing.map { IdentifiedDate(date:$0) } }, set:{ editing = $0?.date })) { NoteEditor(habit:habit, date:$0.date) }
        .sheet(item:$sessionNote) { s in NoteEditor(habit:habit, date:Day.date(s.day) ?? Date(), sessionId:s.id) }
    }
    func dayLabel(_ key: String) -> String {
        guard let d = Day.date(key) else { return key }
        return (key == Day.key(Date()) ? "Today · " : "") + d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
    func noteCard(_ title: String, _ body: String) -> some View {
        VStack(alignment:.leading, spacing:6) {
            HStack { Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Palette.secondary); Spacer(); Text("Edit").font(.footnote.weight(.medium)).foregroundStyle(Palette.teal) }
            Text(body).font(.subheadline).lineLimit(4).multilineTextAlignment(.leading)
        }.frame(maxWidth:.infinity, alignment:.leading).card()
    }
    func emptyCard(_ title: String, _ detail: String) -> some View {
        VStack(spacing:8) { Text(title).font(.subheadline.weight(.semibold)); Text(detail).font(.footnote).foregroundStyle(Palette.secondary) }
            .multilineTextAlignment(.center).frame(maxWidth:.infinity).padding(.vertical,22).padding(.horizontal,16)
            .background(Palette.surface, in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).strokeBorder(Palette.ring, style:StrokeStyle(lineWidth:1.5, dash:[5])))
    }
}
struct IdentifiedDate: Identifiable { let date: Date; var id: Double { date.timeIntervalSince1970 } }
