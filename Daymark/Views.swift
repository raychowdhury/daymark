import StoreKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct RootView: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.requestReview) var requestReview
    @AppStorage("reviewRequestedVersion") var reviewRequestedVersion = ""
    var body: some View {
        Group {
            if store.data.onboarded {
                TabView {
                    NavigationStack { TodayView() }.tabItem { Label("Today", systemImage:"clock") }
                    NavigationStack { ProgressTab() }.tabItem { Label("Progress", systemImage:"chart.bar") }
                    NavigationStack { HabitsView() }.tabItem { Label("Habits", systemImage:"list.bullet") }
                    NavigationStack { SessionsView() }.tabItem { Label("Sessions", systemImage:"stopwatch") }
                }
            } else {
                NavigationStack { WelcomeView() }
            }
        }
        .errorAlert(store)
        .onChange(of:store.reviewMoment) { _, moment in
            guard moment else { return }
            store.reviewMoment = false
            // Once per version; iOS also limits how often the sheet actually appears.
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            guard reviewRequestedVersion != version else { return }
            reviewRequestedVersion = version
            Task { try? await Task.sleep(for:.seconds(1.5)); requestReview() }
        }
        .preferredColorScheme(["light": .light, "dark": .dark][store.data.prefs.appearance] ?? nil)
    }
}
extension View {
    func errorAlert(_ store: HabitStore) -> some View {
        alert("Daymark",isPresented:Binding(get:{store.error != nil},set:{if !$0 { store.error = nil }})) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    func card(_ padding: CGFloat = 14) -> some View {
        self.padding(padding).background(Palette.surface, in:RoundedRectangle(cornerRadius:16)).shadow(color:.black.opacity(0.06), radius:1, y:1)
    }
}

// MARK: Shared pieces

/// Large title on the left, a small accessory on the right (Progress, Habits, Sessions).
struct ScreenHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    var body: some View {
        HStack(alignment:.lastTextBaseline) { Text(title).font(.title.bold()).accessibilityAddTraits(.isHeader); Spacer(); accessory }
            .padding(.horizontal,20).padding(.top,8).padding(.bottom,6).background(Palette.background)
    }
}

struct IconWell: View {
    let habit: Habit
    var size: CGFloat = 40
    var body: some View {
        let live = habit.archivedAt == nil
        Image(systemName:habit.symbol).font(.system(size:size * 0.42, weight:.semibold))
            .foregroundStyle(live ? habit.tint : Palette.secondary)
            .frame(width:size, height:size)
            .background(live ? habit.wash : Palette.chip, in:RoundedRectangle(cornerRadius:size * 0.3))
            .accessibilityHidden(true)
    }
}
struct Rail: View {
    var value: Double
    var color: Color
    var height: CGFloat = 5
    var body: some View {
        Capsule().fill(Palette.track).frame(height:height)
            .overlay(alignment:.leading) { GeometryReader { g in Capsule().fill(color).frame(width:g.size.width * min(1, max(0, value))) } }
            .accessibilityHidden(true)
    }
}
struct Caps: View {
    let text: String
    var color = Palette.secondary
    init(_ text: String, color: Color = Palette.secondary) { self.text = text; self.color = color }
    var body: some View { Text(text).font(.footnote.weight(.semibold)).textCase(.uppercase).kerning(0.3).foregroundStyle(color) }
}
/// 50–56 pt primary buttons from the canvas.
struct BigButton: ButtonStyle {
    var fill = Palette.teal
    var text = Palette.onAccent
    var height: CGFloat = 52
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth:.infinity, minHeight:height)
            .foregroundStyle(text).background(fill, in:RoundedRectangle(cornerRadius:16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
struct Pill: ButtonStyle {
    var fill = Palette.chip
    var text = Palette.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold)).labelStyle(.titleAndIcon).padding(.horizontal,14).frame(minHeight:36)
            .foregroundStyle(text).background(fill, in:Capsule()).opacity(configuration.isPressed ? 0.75 : 1)
    }
}
/// The three stacked day bars of the Daymark mark.
struct DayMark: View {
    var size: CGFloat = 72
    var fill = Palette.teal
    var bar = Color.white
    var opacities: [Double] = [1, 0.85, 0.7]
    var grow = true
    var body: some View {
        VStack(alignment:.leading, spacing:size * 0.1) {
            ForEach(Array(zip([1.0, 0.7, 0.45], opacities).enumerated()), id:\.offset) { i, pair in
                Capsule().fill(bar.opacity(pair.1)).frame(width:(size - size * 0.5) * pair.0, height:size * 0.1)
                    .scaleEffect(x:grow ? 1 : 0.01, anchor:.leading).animation(.spring(duration:0.6).delay(Double(i) * 0.15), value:grow)
            }
        }.frame(width:size, height:size)
            .background(fill, in:RoundedRectangle(cornerRadius:size * 0.3)).accessibilityHidden(true)
    }
}
func timerString(_ ms: Double) -> String { let s = max(0,Int(ceil(ms/1000))); return s >= 3600 ? String(format:"%d:%02d:%02d",s/3600,(s%3600)/60,s%60) : String(format:"%02d:%02d",s/60,s%60) }
func hoursMinutes(_ ms: Double) -> String { let m = Int(ms / 60000); return m >= 60 ? "\(m / 60)h \(String(format:"%02d", m % 60))m" : "\(m) min" }

// MARK: Onboarding

func dayPart(_ date: Date = Date()) -> String { let h = Calendar.current.component(.hour, from:date); return h < 12 ? "morning" : h < 18 ? "afternoon" : "evening" }

struct WelcomeView: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var name = ""
    @State private var shown = false
    var trimmed: String { name.trimmingCharacters(in:.whitespaces) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:28) {
                DayMark(grow:shown)
                Group {
                    VStack(alignment:.leading, spacing:12) {
                        Text(trimmed.isEmpty ? "Small marks,\nsteady days." : "Good \(dayPart()), \(trimmed).").font(.largeTitle.bold())
                        Text("Keep a few habits going without pressure. Check off, focus, look back — no judgment for the gaps.").foregroundStyle(Palette.secondary)
                    }
                    VStack(alignment:.leading, spacing:14) {
                        point("checkmark.circle", Palette.teal, "Daily or flexible.", "Every weekday, or 3 days a week.")
                        point("timer", Palette.indigo, "Focus sessions.", "Pause, resume, log.")
                        point("lock", Palette.teal, "Private by default.", "On your iPhone. No account.")
                    }
                    VStack(alignment:.leading, spacing:8) {
                        (Text("YOUR NAME ").font(.footnote.weight(.semibold)) + Text("(optional)").font(.footnote)).foregroundStyle(Palette.secondary)
                        HStack {
                            TextField("First name", text:$name).textContentType(.givenName).submitLabel(.done)
                            if !trimmed.isEmpty { Button { name = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(Palette.secondary).frame(width:44, height:44) }.accessibilityLabel("Clear name") }
                        }.padding(.leading,16).frame(height:50)
                            .background(Palette.surface, in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(trimmed.isEmpty ? Palette.ring : Palette.teal))
                        Text(trimmed.isEmpty ? "Blank is fine." : "Today opens with “Good \(dayPart()), \(trimmed)”.").font(.footnote).foregroundStyle(Palette.secondary)
                    }
                }.opacity(shown ? 1 : 0).offset(y:shown ? 0 : 10)
            }.padding(24).frame(maxWidth:.infinity, alignment:.leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge:.bottom) {
            VStack(spacing:10) {
                NavigationLink(trimmed.isEmpty ? "Choose a first habit" : "Choose a first habit, \(trimmed)") { FirstHabitView { store.finishOnboarding(adding:$0) } }.buttonStyle(BigButton())
                Text("Reminders stay off until you want them.").font(.caption).foregroundStyle(Palette.secondary)
            }.padding(.horizontal,24).padding(.bottom,8).background(Palette.background)
        }
        .background(Palette.background)
        .toolbar { Button("Skip") { store.finishOnboarding() } }
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration:0.6).delay(0.2)) { shown = true } }
        .onChange(of:name) { _, value in
            if value.count > 24 { name = String(value.prefix(24)) }
            store.data.profile.name = trimmed
        }
    }
    func point(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment:.firstTextBaseline, spacing:12) {
            Image(systemName:symbol).foregroundStyle(color).frame(width:22)
            Text(title).fontWeight(.semibold) + Text(" " + detail).foregroundStyle(Palette.secondary)
        }.font(.subheadline)
    }
}

/// Suggested starters. Used in onboarding and from Today's empty state.
struct FirstHabitView: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.dismiss) var dismiss
    let onDone: ([Habit]) -> Void
    @State private var picked: Set<String> = ["Walk"]
    @State private var creating = false
    static let suggestions: [(Habit, String)] = [
        (Habit(name:"Walk", category:"Body", icon:"walk", color:"sage"), "Body · Check off · Every day"),
        (Habit(name:"Read", category:"Mind", icon:"book", color:"clay", weeklyGoal:4), "Mind · Check off · 4 days a week"),
        (Habit(name:"Drink water", category:"Body", icon:"water", color:"sage", type:"count", target:8, unit:"glasses"), "Body · Count · 8 glasses a day"),
        (Habit(name:"Focused study", category:"Mind", icon:"focus", color:"blue", type:"count", target:25, unit:"minutes", days:[1,2,3,4,5]), "Mind · Minutes · 25 min, weekdays"),
    ]
    var body: some View {
        ScrollView {
            VStack(alignment:.leading, spacing:10) {
                Text("Pick one or two to start").font(.title.bold())
                Text("Start small. Change anything later.").foregroundStyle(Palette.secondary).padding(.bottom,14)
                ForEach(Self.suggestions, id:\.0.name) { habit, detail in
                    let on = picked.contains(habit.name)
                    Button { if on { picked.remove(habit.name) } else { picked.insert(habit.name) } } label: {
                        HStack(spacing:14) {
                            IconWell(habit:habit)
                            VStack(alignment:.leading, spacing:2) { Text(habit.name).font(.headline); Text(detail).font(.footnote).foregroundStyle(Palette.secondary) }
                            Spacer()
                            Image(systemName:on ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(on ? Palette.teal : Palette.ring)
                        }.frame(minHeight:44).card().overlay(RoundedRectangle(cornerRadius:16).stroke(on ? Palette.teal : .clear, lineWidth:2))
                    }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
                Button { creating = true } label: {
                    HStack(spacing:14) {
                        Image(systemName:"plus").font(.headline).foregroundStyle(Palette.teal).frame(width:40, height:40).background(Palette.chip, in:RoundedRectangle(cornerRadius:12))
                        VStack(alignment:.leading, spacing:2) { Text("Create my own").font(.headline).foregroundStyle(Palette.teal); Text("Name, target, schedule").font(.footnote).foregroundStyle(Palette.secondary) }
                        Spacer()
                    }.padding(14).overlay(RoundedRectangle(cornerRadius:16).strokeBorder(Palette.ring, style:StrokeStyle(lineWidth:1.5, dash:[5])))
                }.buttonStyle(.plain)
            }.padding(24)
        }
        .safeAreaInset(edge:.bottom) {
            VStack(spacing:10) {
                Button(picked.isEmpty ? "Continue" : picked.count == 1 ? "Start with 1 habit" : "Start with \(picked.count) habits") {
                    onDone(Self.suggestions.map(\.0).filter { picked.contains($0.name) }.map { var h = $0; h.id = UUID().uuidString; h.createdAt = Day.key(Date()); h.reminder = false; return h })
                    dismiss()
                }.buttonStyle(BigButton())
                Text("No notifications unless you add a reminder.").font(.caption).foregroundStyle(Palette.secondary)
            }.padding(.horizontal,24).padding(.bottom,8).background(Palette.background)
        }
        .background(Palette.background)
        .toolbar { if !store.data.onboarded { Button("Skip") { store.finishOnboarding() } } }
        .sheet(isPresented:$creating, onDismiss:{ if !store.data.habits.isEmpty && !store.data.onboarded { onDone([]) } }) { HabitEditor() }
    }
}

// MARK: Settings

struct SettingsView: View {
    @EnvironmentObject var store: HabitStore
    @Environment(\.dismiss) var dismiss
    @State private var export = false
    @State private var importing = false
    @State private var pending: Data?
    @State private var confirm = false
    @State private var erase = false
    @State private var document = BackupDocument(data:Data())
    @State private var exportCSV = false
    @State private var cloudChoice = false
    var permissionText: String {
        switch store.permission { case .authorized, .provisional, .ephemeral: return "Allowed"; case .denied: return "Off in iPhone Settings"; default: return "Not requested yet" }
    }
    static let otherApps = [
        (id:"6806044644", name:"SelfMastery 30", detail:"30 days. One meaningful change.", symbol:"target"),
        (id:"6819523988", name:"OathSteps", detail:"Citizenship test prep", symbol:"flag"),
        (id:"6765990601", name:"Azan: Prayer Times", detail:"Prayer times, wherever you are", symbol:"moon.stars"),
    ]
    func pref<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get:{ store.data.prefs[keyPath:key] }, set:{ store.data.prefs[keyPath:key] = $0; store.save(); store.scheduleReminders() })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing:14) {
                        Text(store.data.profile.name.first.map(String.init) ?? "·").font(.headline).foregroundStyle(Palette.onAccent).frame(width:40, height:40).background(Palette.teal, in:Circle()).accessibilityHidden(true)
                        VStack(alignment:.leading, spacing:2) {
                            TextField("Your name", text:Binding(get:{store.data.profile.name}, set:{store.data.profile.name = String($0.prefix(60)); store.save()})).font(.headline)
                            Text("Greeting name").font(.footnote).foregroundStyle(Palette.secondary)
                        }
                    }
                }
                Section {
                    Toggle("Habit reminders", isOn:Binding(get:{store.reminders}, set:{ enabled in if enabled { Task { await store.requestReminders() } } else { store.reminders = false; store.data.remindersEnabled = false; store.save(); UNUserNotificationCenter.current().removeAllPendingNotificationRequests() } }))
                    LabeledContent("Notification permission") { Text(permissionText).foregroundStyle(store.permission == .authorized ? Palette.teal : Palette.secondary) }
                    if store.permission == .denied, let url = URL(string:UIApplication.openSettingsURLString) { Link("Open iPhone Settings", destination:url) }
                    Picker("Default lead time", selection:pref(\.leadMinutes)) { Text("At start time").tag(0); ForEach([5, 10, 15, 30], id:\.self) { Text("\($0) min before").tag($0) } }
                } header: { Text("Reminders") } footer: { Text("Each habit sets its own reminder. This switch pauses them all.") }
                Section {
                    Picker("Default duration", selection:pref(\.defaultMinutes)) { ForEach([5, 15, 25, 45, 60], id:\.self) { Text("\($0) min").tag($0) } }
                    Toggle("Lock Screen timer", isOn:pref(\.liveActivity))
                    Toggle("End-of-session sound", isOn:pref(\.endSound))
                } header: { Text("Focus") } footer: { Text("Timers stay accurate in the background.") }
                Section {
                    Picker("Week starts on", selection:pref(\.mondayFirst)) { Text("Monday").tag(true); Text("Sunday").tag(false) }
                    Picker("Appearance", selection:pref(\.appearance)) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                } header: { Text("Week & appearance") } footer: { Text("Weekly goals reset on this day.") }
                Section {
                    Toggle("iCloud sync", isOn:Binding(get:{ store.data.prefs.iCloud }, set:{ on in if !on { store.disableCloud() } else if store.cloudCopy != nil { cloudChoice = true } else { store.enableCloud(useCloud:false) } }))
                    Button("Export history (CSV)", systemImage:"tablecells") { document = BackupDocument(data:store.csv()); exportCSV = true; export = true }
                    Button("Export backup", systemImage:"square.and.arrow.up") { document = BackupDocument(data:store.backup()); exportCSV = false; export = true }
                    Button("Import backup", systemImage:"square.and.arrow.down") { importing = true }
                    Button("Erase all data…", role:.destructive) { erase = true }
                } header: { Text("Data") } footer: { Text(store.data.prefs.iCloud ? "Synced through your iCloud account. The newest copy wins if two devices change at once." : "Records stay on this iPhone. Export a backup to move data from the web tracker.") }
                Section("More from the developer") {
                    ForEach(Self.otherApps, id:\.id) { app in
                        Link(destination:URL(string:"https://apps.apple.com/app/id\(app.id)")!) {
                            HStack(spacing:12) {
                                Image(systemName:app.symbol).font(.headline).foregroundStyle(Palette.teal).frame(width:36, height:36).background(Palette.tealTint, in:RoundedRectangle(cornerRadius:10))
                                VStack(alignment:.leading, spacing:1) { Text(app.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text); Text(app.detail).font(.footnote).foregroundStyle(Palette.secondary) }
                                Spacer()
                                Image(systemName:"arrow.up.right").font(.footnote).foregroundStyle(Palette.secondary)
                            }
                        }.accessibilityHint("Opens the App Store")
                    }
                }
                Section {
                    Text("Daymark · " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")).font(.footnote).foregroundStyle(Palette.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(Palette.grouped)
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.fontWeight(.semibold) }
            .fileExporter(isPresented:$export,document:document,contentType:exportCSV ? .commaSeparatedText : .json,defaultFilename:exportCSV ? "Daymark-history" : "Daymark-backup") { result in if case .failure(let error) = result { store.error = error.localizedDescription } }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
                do { let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }; pending = try Data(contentsOf:url); confirm = true } catch { store.error = error.localizedDescription }
            }
            .errorAlert(store)
            .confirmationDialog("Replace your current data with this backup? Export first if you want to keep a copy.",isPresented:$confirm,titleVisibility:.visible) { Button("Import and replace",role:.destructive) { do { if let bytes = pending { try store.importBackup(bytes) } } catch { store.error = error.localizedDescription }; pending = nil }; Button("Cancel",role:.cancel) { pending = nil } }
            .confirmationDialog("iCloud already has Daymark data. Which copy should this iPhone use?", isPresented:$cloudChoice, titleVisibility:.visible) {
                Button("Use the iCloud copy") { store.enableCloud(useCloud:true) }
                Button("Keep this iPhone's data") { store.enableCloud(useCloud:false) }
            } message: { Text("The copy you don't choose is replaced on this iPhone or in iCloud.") }
            .confirmationDialog("Erase all habits, check-ins, notes and sessions from this iPhone?", isPresented:$erase, titleVisibility:.visible) { Button("Erase everything", role:.destructive) { store.erase(); dismiss() } } message: { Text("This can't be undone. Export a backup first if you might want them back.") }
        }
    }
}
