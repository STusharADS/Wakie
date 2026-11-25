//
//  WakieWidget.swift
//  WakieWidget
//
//  "Next Alarm" widget: the next Wakie alarm, its challenge mascot and a live countdown.
//  Reads the upcoming rings the app shares through the app group (see WidgetBridge.swift).
//

import WidgetKit
import SwiftUI

// MARK: - Shared data

/// Mirror of the app's `WidgetAlarmOccurrence`; the coding keys must match.
struct WidgetAlarmOccurrence: Codable {
    let fireDate: Date
    let timeText: String
    let periodText: String
    let mission: String
    let repeatText: String
    let placeLabel: String?

    var missionTitle: String {
        switch mission {
        case "pickiePicky": "Pickie-Picky"
        case "blahBlah": "Blah-Blah"
        default: "Shaky-Shaky"
        }
    }

    var mascot: String {
        switch mission {
        case "pickiePicky": "PickyPicky"
        case "blahBlah": "BlahBlah"
        default: "ShakyShaky"
        }
    }

    var missionColor: Color {
        switch mission {
        case "pickiePicky": Color(red: 0.78, green: 0.70, blue: 1.0)   // lavender
        case "blahBlah": Color(red: 1.0, green: 0.71, blue: 0.60)      // peach
        default: Color(red: 1.0, green: 0.83, blue: 0.23)              // yellow
        }
    }

    static let sample = WidgetAlarmOccurrence(fireDate: .now.addingTimeInterval(3 * 3600 + 720), timeText: "6:13",
                                              periodText: "AM", mission: "shakyShaky", repeatText: "Weekdays", placeLabel: nil)
}

private enum SharedStore {
    static let appGroupID = "group.ts.Wakie"
    static let occurrencesKey = "widgetUpcomingAlarms"

    static func upcoming(after date: Date) -> [WidgetAlarmOccurrence] {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: occurrencesKey),
              let all = try? JSONDecoder().decode([WidgetAlarmOccurrence].self, from: data) else { return [] }
        return all.filter { $0.fireDate > date }
    }
}

// MARK: - Timeline

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    /// `nil` when no alarm is set.
    let next: WidgetAlarmOccurrence?
}

struct NextAlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAlarmEntry {
        NextAlarmEntry(date: .now, next: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        let next = SharedStore.upcoming(after: .now).first
        completion(NextAlarmEntry(date: .now, next: context.isPreview ? (next ?? .sample) : next))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let now = Date.now
        let upcoming = SharedStore.upcoming(after: now)
        // One entry now, then one the moment each alarm rings so the widget moves on to the next one.
        var entries = [NextAlarmEntry(date: now, next: upcoming.first)]
        for (index, ring) in upcoming.prefix(10).enumerated() {
            entries.append(NextAlarmEntry(date: ring.fireDate.addingTimeInterval(1), next: upcoming.dropFirst(index + 1).first))
        }
        // Ask again in a day at the latest, so repeating alarms keep rolling forward.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(24 * 3600))))
    }
}

// MARK: - Views

private let ink = Color(red: 0.12, green: 0.10, blue: 0.24)
private let purpleTop = Color(red: 0.23, green: 0.16, blue: 0.53)
private let purpleBottom = Color(red: 0.43, green: 0.31, blue: 0.78)

struct WakieWidgetEntryView: View {
    let entry: NextAlarmEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let next = entry.next {
                HStack(alignment: .top) {
                    Image(next.mascot)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                    Spacer(minLength: 0)
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                timeLabel(next, size: 34)
                Text(next.fireDate, style: .relative)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                missionChip(next)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            if let next = entry.next {
                Image(next.mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next alarm")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                    timeLabel(next, size: 40)
                    HStack(spacing: 4) {
                        Text("Rings in")
                        Text(next.fireDate, style: .relative)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    HStack(spacing: 6) {
                        missionChip(next)
                        Text(next.placeLabel ?? next.repeatText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Image("ShakyShaky")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 90, height: 90)
                emptyState
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text("No alarms")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Tap to set a Wakie alarm")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func timeLabel(_ next: WidgetAlarmOccurrence, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(next.timeText)
                .font(.system(size: size, weight: .black, design: .rounded))
            Text(next.periodText)
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .monospacedDigit()
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }

    private func missionChip(_ next: WidgetAlarmOccurrence) -> some View {
        Text(next.missionTitle)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(next.missionColor))
            .lineLimit(1)
    }

    // MARK: Lock Screen

    private var inline: some View {
        if let next = entry.next {
            Label("\(next.timeText) \(next.periodText) · \(next.missionTitle)", systemImage: "alarm.fill")
        } else {
            Label("No Wakie alarms", systemImage: "alarm")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 12, weight: .bold))
                if let next = entry.next {
                    Text(next.timeText)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.6)
                    Text(next.periodText)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                } else {
                    Text("--")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                }
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let next = entry.next {
                Label("Wakie · \(next.missionTitle)", systemImage: "alarm.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("\(next.timeText) \(next.periodText)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                Text(next.fireDate, style: .relative)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } else {
                Label("Wakie", systemImage: "alarm")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text("No alarms set")
                    .font(.system(size: 16, weight: .black, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct WakieWidget: Widget {
    let kind: String = "WakieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextAlarmProvider()) { entry in
            WakieWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [purpleTop, purpleBottom], startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Next Alarm")
        .description("See your next Wakie alarm and its challenge.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    WakieWidget()
} timeline: {
    NextAlarmEntry(date: .now, next: .sample)
    NextAlarmEntry(date: .now, next: nil)
}

#Preview(as: .systemMedium) {
    WakieWidget()
} timeline: {
    NextAlarmEntry(date: .now, next: .sample)
}

#Preview(as: .accessoryRectangular) {
    WakieWidget()
} timeline: {
    NextAlarmEntry(date: .now, next: .sample)
}
