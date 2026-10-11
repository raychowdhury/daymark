import ActivityKit
import SwiftUI
import WidgetKit

@main struct DaymarkWidgets: WidgetBundle {
    var body: some Widget { FocusActivityWidget() }
}

/// Canvas tokens: focus indigo, warning for paused.
private let indigo = Color(red:0x9B/255, green:0x9D/255, blue:0xF0/255)
private let amber = Color(red:0xF0/255, green:0xC3/255, blue:0x6D/255)
private let muted = Color(red:0xA3/255, green:0xB0/255, blue:0xAB/255)

struct FocusActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:FocusAttributes.self) { context in
            HStack(spacing:14) {
                Image(systemName:context.attributes.symbol).font(.title3.weight(.semibold)).foregroundStyle(indigo)
                    .frame(width:44, height:44).background(indigo.opacity(0.18), in:RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading, spacing:2) {
                    Text(context.attributes.habit).font(.headline).foregroundStyle(.white)
                    Label(context.state.paused ? "Paused" : "Focus · \(context.attributes.minutes) min", systemImage:context.state.paused ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(context.state.paused ? amber : muted)
                }
                Spacer()
                clock(context.state).font(.system(size:34, weight:.light, design:.rounded)).foregroundStyle(context.state.paused ? muted : .white)
            }
            .padding(16)
            .activityBackgroundTint(Color(red:0x10/255, green:0x1A/255, blue:0x1A/255))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName:context.attributes.symbol).font(.title2).foregroundStyle(indigo).padding(.leading,4) }
                DynamicIslandExpandedRegion(.trailing) { clock(context.state).font(.title2.weight(.light)).foregroundStyle(context.state.paused ? amber : .white).padding(.trailing,4) }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.habit).font(.headline).lineLimit(1) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.paused ? "Paused · paused time doesn't count" : "\(context.attributes.category) · Focus session").font(.caption).foregroundStyle(muted) }
            } compactLeading: {
                Image(systemName:context.state.paused ? "pause.fill" : "timer").foregroundStyle(context.state.paused ? amber : indigo)
            } compactTrailing: {
                clock(context.state).font(.caption.weight(.semibold)).foregroundStyle(context.state.paused ? amber : indigo).frame(maxWidth:44)
            } minimal: {
                Image(systemName:"timer").foregroundStyle(indigo)
            }
            .keylineTint(indigo)
        }
    }
    @ViewBuilder func clock(_ state: FocusAttributes.ContentState) -> some View {
        if let end = state.endsAt, !state.paused, end > .now {
            Text(timerInterval:Date.now...end, countsDown:true).monospacedDigit().multilineTextAlignment(.trailing)
        } else {
            Text(Duration.seconds(max(0, state.remaining)).formatted(.time(pattern:.minuteSecond))).monospacedDigit()
        }
    }
}
