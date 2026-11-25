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
        // An entry now, one just after each alarm rings (so the widget moves on to the next one),
        // and one every 15 minutes for a few hours so the starry background twinkles.
        var dates = [now]
        dates += upcoming.prefix(10).map { $0.fireDate.addingTimeInterval(1) }
        dates += (1...16).map { now.addingTimeInterval(Double($0) * 15 * 60) }
        let entries = dates.sorted().map { date in
            NextAlarmEntry(date: date, next: upcoming.first { $0.fireDate > date })
        }
        // Ask again in a day at the latest, so repeating alarms keep rolling forward.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(24 * 3600))))
    }
}

// MARK: - Views

private let ink = Color(red: 0.12, green: 0.10, blue: 0.24)
/// The app's night sky colour (#001120), deepened toward black at the bottom for contrast.
private let nightSky = Color(red: 0, green: 17 / 255, blue: 32 / 255)
private let nightSkyDeep = Color(red: 0, green: 6 / 255, blue: 14 / 255)
private let wakieYellow = Color(red: 1.0, green: 0.83, blue: 0.23)
private let wakieLavender = Color(red: 0.78, green: 0.70, blue: 1.0)
private let wakiePurple = Color(red: 0.55, green: 0.42, blue: 0.96)

/// The app's dark background: night sky, stars and soft hills along the bottom.
/// Widgets can't animate continuously, so the stars' brightness shifts with each
/// timeline entry to give a gentle twinkle over the day.
struct WidgetNightBackground: View {
    let date: Date

    private struct Star {
        let x, y, radius, brightness, phase: Double
        let isSparkle: Bool
    }

    private static let stars: [Star] = {
        var seed: UInt64 = 0x5EED_CAFE
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        return (0..<46).map { index in
            let sparkle = index % 8 == 0
            return Star(x: next(), y: pow(next(), 1.3) * 0.8,
                        radius: sparkle ? 3 + next() * 2.5 : 0.6 + next() * 1.4,
                        brightness: 0.65 + next() * 0.35, phase: next() * .pi * 2, isSparkle: sparkle)
        }
    }()

    var body: some View {
        let t = date.timeIntervalSinceReferenceDate / 600
        ZStack {
            LinearGradient(colors: [nightSky, nightSkyDeep], startPoint: .top, endPoint: .bottom)
            Canvas { canvas, size in
                for star in Self.stars {
                    let twinkle = 0.6 + 0.4 * sin(t + star.phase)
                    let c = CGPoint(x: star.x * size.width, y: star.y * size.height)
                    let r = star.radius
                    let path = star.isSparkle
                        ? Self.sparkle(center: c, radius: r)
                        : Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                    canvas.fill(path, with: .color(.white.opacity(star.brightness * twinkle)))
                }
            }
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    Ellipse()
                        .fill(LinearGradient(colors: [wakieLavender.opacity(0.7), wakiePurple.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.9, height: h * 0.45)
                        .position(x: w * 0.08, y: h * 1.02)
                    Ellipse()
                        .fill(LinearGradient(colors: [wakieYellow.opacity(0.55), wakieYellow.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.75, height: h * 0.35)
                        .position(x: w * 0.6, y: h * 1.06)
                    Ellipse()
                        .fill(LinearGradient(colors: [wakieLavender.opacity(0.7), wakiePurple.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.7, height: h * 0.45)
                        .position(x: w * 1.0, y: h * 1.0)
                }
                .blur(radius: 6)
            }
        }
    }

    private static func sparkle(center c: CGPoint, radius r: Double) -> Path {
        var p = Path()
        let inner = r * 0.28
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + inner, y: c.y - inner))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + inner, y: c.y + inner))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - inner, y: c.y + inner))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - inner, y: c.y - inner))
        p.closeSubpath()
        return p
    }
}

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
                    mascot(next.mascot, size: 72)
                    Spacer(minLength: 0)
                    Label("Wakie", systemImage: "alarm.fill")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(wakieYellow)
                }
                Spacer(minLength: 0)
                timeLabel(next, size: 34)
                Text(next.fireDate, style: .relative)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(wakieYellow)
                    .lineLimit(1)
                missionChip(next)
                    .padding(.top, 2)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            if let next = entry.next {
                mascot(next.mascot, size: 124)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Next alarm", systemImage: "alarm.fill")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(wakieYellow)
                    timeLabel(next, size: 40)
                    HStack(spacing: 4) {
                        Text("Rings in")
                        Text(next.fireDate, style: .relative)
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
                mascot("ShakyShaky", size: 100)
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

    /// The mascot artwork has wide transparent margins, so it's enlarged to fill its frame.
    private func mascot(_ name: String, size: CGFloat) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .scaleEffect(1.7)
            .frame(width: size, height: size)
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
                    WidgetNightBackground(date: entry.date)
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
