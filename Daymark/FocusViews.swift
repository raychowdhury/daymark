import SwiftUI

/// Duration chips plus a ±5 min custom stepper, 1–180 minutes.
struct DurationPicker: View {
    @Binding var minutes: Int
    @State private var custom = false
    var body: some View {
        VStack(alignment:.leading, spacing:10) {
            HStack(spacing:6) {
                ForEach([5, 15, 25, 45], id:\.self) { m in chip("\(m) min", on:!custom && minutes == m) { custom = false; minutes = m } }
                chip("Custom", on:custom) { custom = true }
            }.dynamicTypeSize(...DynamicTypeSize.xxLarge)
            if custom {
                HStack {
                    Text("Minutes").font(.subheadline.weight(.medium))
                    Spacer()
                    stepButton("minus", "Five minutes less") { minutes = max(1, minutes - 5) }
                    Text("\(minutes)").font(.headline.monospacedDigit()).frame(minWidth:48).accessibilityLabel("\(minutes) minutes")
                    stepButton("plus", "Five minutes more") { minutes = min(180, minutes + 5) }
                }.padding(.leading,16).padding(8).background(Palette.background, in:RoundedRectangle(cornerRadius:14))
                Text("1–180 min. Pausing stops the clock.").font(.caption).foregroundStyle(Palette.secondary)
            }
        }
        .onAppear { custom = ![5, 15, 25, 45].contains(minutes) }
    }
    func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action:action) { Text(label).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal,4).frame(maxWidth:.infinity, minHeight:40).contentShape(Capsule()) }
            .foregroundStyle(on ? Palette.indigo : Palette.text)
            .background(on ? Palette.indigoTint : Palette.surface, in:Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : Palette.ring, lineWidth:1.5))
            .accessibilityAddTraits(on ? .isSelected : [])
    }
    func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:symbol).font(.headline).foregroundStyle(Palette.indigo).frame(width:44, height:44).background(Palette.surface, in:RoundedRectangle(cornerRadius:12)) }
            .accessibilityLabel(label)
    }
}

/// Asks before an unfinished session is replaced: log it first, discard it, or keep it.
struct ReplaceDialog: ViewModifier {
    @EnvironmentObject var store: HabitStore
    @Binding var pending: Int?
    let habit: Habit
    let onStart: () -> Void
    func body(content: Content) -> some View {
        let current = store.data.timer
        let currentName = store.data.habits.first { $0.id == current?.id }?.name ?? "the current session"
        let same = current?.id == habit.id
        content.confirmationDialog(same ? "Replace the current session?" : "Replace the running session?", isPresented:Binding(get:{ pending != nil }, set:{ if !$0 { pending = nil } }), titleVisibility:.visible) {
            if current?.canLogIfEnded == true {
                Button("Log \(current!.focusedMinutes) min, then start" + (same ? "" : " \(habit.name)")) { go(log:true) }
            }
            Button(same ? "Start \(pending ?? 0) min anyway" : "Discard and start \(habit.name)", role:.destructive) { go(log:false) }
            Button("Keep going", role:.cancel) { pending = nil }
        } message: {
            Text(current.map { same ? "\($0.focusedMinutes) unlogged minutes will be lost." : "\(currentName) has \($0.focusedMinutes) unlogged minutes." } ?? "")
        }
    }
    func go(log: Bool) { if let m = pending { store.start(habit, minutes:m, logCurrent:log); pending = nil; onStart() } }
}
extension FocusTimer {
    /// Whether ending this unfinished session now would leave something worth logging.
    var canLogIfEnded: Bool { !logged && focused() >= 60000 }
}

/// Compact sheet for picking a duration before a session starts.
struct FocusSetup: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.dismiss) var dismiss
    let habit: Habit
    let onStart: () -> Void
    @State private var minutes = 25
    @State private var pending: Int?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading, spacing:18) {
                    HStack(spacing:18) {
                        ZStack { Circle().stroke(Palette.indigoTint, lineWidth:6); Image(systemName:habit.symbol).foregroundStyle(Palette.indigo) }.frame(width:64, height:64).accessibilityHidden(true)
                        VStack(alignment:.leading, spacing:2) {
                            Text(timerString(Double(minutes) * 60000)).font(.system(size:34, weight:.light, design:.rounded).monospacedDigit())
                            Text(readyLine).font(.footnote).foregroundStyle(Palette.secondary)
                        }
                    }.padding(16).frame(maxWidth:.infinity, alignment:.leading).background(Palette.background, in:RoundedRectangle(cornerRadius:18))
                    Caps("Duration")
                    DurationPicker(minutes:$minutes)
                    Button("Start \(minutes) minutes", systemImage:"play.fill") {
                        if let t = store.data.timer, t.status != "finished" { pending = minutes } else { store.start(habit, minutes:minutes); started() }
                    }.buttonStyle(BigButton(fill:Palette.indigo, height:56))
                }.padding(20)
            }
            .background(Palette.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.principal) { VStack(spacing:0) { Text("Focus").font(.headline); Text(habit.name).font(.caption).foregroundStyle(Palette.secondary) } }
            }
            .modifier(ReplaceDialog(pending:$pending, habit:habit, onStart:started))
        }
        .tint(Palette.indigo)
        .presentationDetents([.medium, .large])
        .onAppear { minutes = habit.isMinutes ? min(max(habit.target - store.amount(habit), 5), 180) : store.data.prefs.defaultMinutes }
    }
    var readyLine: String {
        habit.isMinutes ? "Ready · \(store.amount(habit)) of \(habit.target) min today" : "Ready"
    }
    func started() { onStart(); dismiss() }
}

/// Full-screen, always-dark timer for the active session.
struct FocusScreen: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.dismiss) var dismiss
    @State private var pending: Int?
    @State private var note = false
    var body: some View {
        Group {
            if let t = store.data.timer, let h = store.data.habits.first(where:{ $0.id == t.id }) { screen(t, h) }
            else { Color.clear.onAppear { dismiss() } }
        }
        .background(Palette.background)
        .preferredColorScheme(.dark)
    }
    func screen(_ t: FocusTimer, _ h: Habit) -> some View {
        let finished = t.status == "finished"
        let stopped = finished && t.remainingMs > 0
        let (label, color): (String, Color) = t.logged ? ("Logged", Palette.teal) : stopped ? ("Stopped early", Palette.secondary) : finished ? ("Completed", Palette.teal) : t.status == "paused" ? ("Paused", Palette.warning) : ("Running", Palette.indigo)
        let focusedMin = Int(t.focused() / 60000)
        let subline = t.logged ? "Saved"
            : stopped ? "\(focusedMin) of \(Int(t.durationMs / 60000)) min"
            : finished ? "\(Int(t.durationMs / 60000)) min done"
            : t.status == "paused" ? "\(focusedMin) min focused"
            : "of \(Int(t.durationMs / 60000)) · ends " + (t.endsAt.map { Date(timeIntervalSince1970:$0 / 1000).formatted(date:.omitted, time:.shortened) } ?? "")
        return VStack(spacing:0) {
            HStack {
                circleButton(finished ? "xmark" : "chevron.down", finished ? "Close" : "Minimize") { if finished && (t.logged || !t.canLog) { store.dismissTimer() }; dismiss() }
                Spacer()
                HStack(spacing:8) { Circle().fill(color).frame(width:8, height:8); Caps(label, color:color) }.accessibilityElement(children:.combine)
                Spacer()
                if finished { Color.clear.frame(width:44, height:44) } else { Button("End") { store.finish("stopped") }.font(.subheadline.weight(.medium)).foregroundStyle(Palette.secondary).frame(minWidth:44, minHeight:44) }
            }
            VStack(spacing:4) { Caps("\(h.category) · Focus session"); Text(h.name).font(.title2.bold()).multilineTextAlignment(.center) }.padding(.top,22)
            Spacer(minLength:16)
            ZStack {
                Circle().stroke(Palette.track, lineWidth:12)
                Circle().trim(from:0, to:finished ? 1 : CGFloat(t.remaining() / t.durationMs)).stroke(color, style:StrokeStyle(lineWidth:12, lineCap:.round)).rotationEffect(.degrees(-90))
                VStack(spacing:6) {
                    Text(timerString(finished ? t.focused() : t.remaining())).font(.system(size:72, weight:.light, design:.rounded).monospacedDigit()).foregroundStyle(t.status == "paused" ? Palette.secondary : Palette.text).minimumScaleFactor(0.4).lineLimit(1)
                    Text(subline).font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                }.padding(28)
            }
            .frame(maxWidth:280, maxHeight:280)
            .accessibilityElement(children:.ignore).accessibilityLabel("\(label), \(finished ? subline : timerString(t.remaining()) + " remaining")")
            Spacer(minLength:16)
            if finished { finishedControls(t, h, stopped:stopped) } else { activeControls(t, h) }
        }
        .padding(.horizontal,24).padding(.vertical,12)
        .modifier(ReplaceDialog(pending:$pending, habit:h, onStart:{}))
        .sheet(isPresented:$note) { NoteEditor(habit:h, date:Day.date(t.day) ?? Date(), sessionId:t.sessionId) }
    }
    func activeControls(_ t: FocusTimer, _ h: Habit) -> some View {
        VStack(alignment:.leading, spacing:10) {
            HStack { Caps("Duration"); Spacer(); Text("Paused time doesn't count").font(.footnote).foregroundStyle(Palette.secondary) }
            DurationPicker(minutes:Binding(get:{ Int(t.durationMs / 60000) }, set:{ m in if m != Int(t.durationMs / 60000) { if t.focused() > 1000 { pending = m } else { store.start(h, minutes:m) } } }))
            GeometryReader { g in
                HStack(spacing:10) {
                    Button("Restart", systemImage:"arrow.counterclockwise") { store.restart() }.buttonStyle(BigButton(fill:Palette.surface, text:Palette.text)).frame(width:(g.size.width - 10) / 2.4)
                    Button(t.status == "running" ? "Pause" : "Resume", systemImage:t.status == "running" ? "pause.fill" : "play.fill") { store.pauseResume() }.buttonStyle(BigButton(fill:Palette.indigo))
                }
            }.frame(height:52).padding(.top,10)
            if t.status == "paused" { Button("End session") { store.finish("stopped") }.foregroundStyle(Palette.secondary).frame(maxWidth:.infinity, minHeight:44) }
        }
    }
    @ViewBuilder func finishedControls(_ t: FocusTimer, _ h: Habit, stopped: Bool) -> some View {
        let logLabel = h.isMinutes ? "Log \(t.focusedMinutes) min" : "Mark habit complete"
        VStack(spacing:12) {
            if t.logged {
                HStack(spacing:12) {
                    Image(systemName:"checkmark.circle.fill").font(.title2).foregroundStyle(Palette.teal)
                    VStack(alignment:.leading, spacing:2) {
                        Text(h.isMinutes ? "Logged \(t.focusedMinutes) min" : "Marked complete").font(.subheadline.weight(.semibold))
                        Text(h.isMinutes ? "\(store.amount(h, Day.date(t.day) ?? Date())) of \(h.target) min " + (t.day == Day.key(Date()) ? "today" : "that day") : h.name).font(.footnote).foregroundStyle(Palette.secondary)
                    }
                    Spacer(minLength:0)
                }.padding(14).background(Palette.tealTint, in:RoundedRectangle(cornerRadius:16)).accessibilityElement(children:.combine)
                Button("Logged") {}.buttonStyle(BigButton(fill:Palette.surface, text:Palette.secondary)).disabled(true).opacity(0.7)
                HStack(spacing:10) {
                    Button("Add a note") { note = true }.buttonStyle(BigButton(fill:Palette.surface, text:Palette.text, height:48))
                    Button("Back to Today") { store.dismissTimer(); dismiss() }.buttonStyle(BigButton(height:48))
                }
            } else {
                if t.canLog {
                    VStack(alignment:.leading, spacing:6) {
                        Text("Log it?").font(.subheadline.weight(.semibold))
                        Text("Timers don't update habits by themselves. " + (h.isMinutes ? "Logging adds \(t.focusedMinutes) min to today's \(store.amount(h, Day.date(t.day) ?? Date())) of \(h.target)." : "Logging marks \(h.name) complete.")).font(.footnote).foregroundStyle(Palette.secondary)
                    }.padding(14).frame(maxWidth:.infinity, alignment:.leading).background(Palette.surface, in:RoundedRectangle(cornerRadius:16))
                    Button(logLabel) { store.logTimer() }.buttonStyle(BigButton())
                } else {
                    Text("Under a minute — nothing to log.").font(.footnote).foregroundStyle(Palette.secondary)
                }
                HStack(spacing:10) {
                    Button("Run another") { store.restart() }.buttonStyle(BigButton(fill:Palette.surface, text:Palette.text, height:48))
                    Button(t.canLog ? "Don't log" : "Close") { store.dismissTimer(); dismiss() }.buttonStyle(BigButton(fill:.clear, text:Palette.secondary, height:48))
                }
            }
        }
    }
    func circleButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:symbol).font(.headline).foregroundStyle(Palette.text).frame(width:44, height:44).background(Palette.surface, in:Circle()) }.accessibilityLabel(label)
    }
}
