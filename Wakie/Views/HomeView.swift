//
//  HomeView.swift
//  Wakie
//
//  Dashboard: greeting, add-alarm button, the next alarm, missions to try and stats.
//

import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    @State private var practice: MissionRun?
    @State private var editingAlarm: WakieAlarm?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                upcomingCard
                challenges
                statsRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .fullScreenCover(item: $practice) { run in
            MissionView(run: run)
        }
        .sheet(item: $editingAlarm) { alarm in
            EditAlarmView(alarm: alarm, isNew: !model.alarms.contains { $0.id == alarm.id })
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            TimelineView(.everyMinute) { context in
                HStack(alignment: .top, spacing: 2) {
                    Text(greeting(for: context.date))
                        .font(.wakie(38, .black))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(-6)
                    SparkleLines(size: 26)
                        .rotationEffect(.degrees(60))
                }
            }
            Spacer()
            // Adding an alarm is the main thing people do here, so it gets the big pulsing button.
            AddAlarmButton { editingAlarm = WakieAlarm() }
                .padding(.top, 4)
        }
    }

    private func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good\nMorning!"
        case 12..<17: "Good\nAfternoon!"
        case 17..<22: "Good\nEvening!"
        default: "Sweet\nDreams!"
        }
    }

    // MARK: Upcoming alarm

    private var upcomingCard: some View {
        TimelineView(.everyMinute) { context in
            let next = model.upcoming
            Button {
                if let next {
                    editingAlarm = next.alarm
                } else {
                    editingAlarm = WakieAlarm()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "alarm")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    // Title, time and countdown share one leading edge.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next == nil ? "No Upcoming Alarm" : "Upcoming Alarm")
                            .font(.wakie(15, .bold))
                            .foregroundStyle(Theme.ink)
                        if let next {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(next.alarm.timeText)
                                    .font(.wakie(42, .black))
                                Text(next.alarm.periodText)
                                    .font(.wakie(22, .heavy))
                                // Flag shows whose clock this time belongs to.
                                if !next.alarm.isLocal {
                                    Text(next.alarm.placeFlag ?? "🌍")
                                        .font(.system(size: 22))
                                        .accessibilityLabel(next.alarm.placeName ?? "Another time zone")
                                }
                            }
                            .foregroundStyle(Theme.ink)
                        } else {
                            Text("Set one")
                                .font(.wakie(32, .black))
                                .foregroundStyle(Theme.ink)
                        }
                        HStack(spacing: 8) {
                            Text(next.map { ringsInText(from: context.date, to: $0.date) } ?? "Tap the + above to add one")
                                .font(.wakie(14, .semibold))
                                .foregroundStyle(Theme.inkSecondary)
                            // The same ring time on the phone's own clock.
                            if let next, !next.alarm.isLocal {
                                Text("· \(next.date.formatted(date: .omitted, time: .shortened)) here")
                                    .font(.wakie(13, .semibold))
                                    .foregroundStyle(.gray)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    if next != nil {
                        Image(systemName: "pencil")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Color(hex: 0x1E1A3C))
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Theme.yellow).shadow(color: Theme.yellowDeep.opacity(0.5), radius: 6, y: 3))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .liquidGlassCard(radius: 32)
                .overlay(alignment: .topTrailing) {
                    if let next {
                        MascotImage(mission: next.alarm.mission, size: 64)
                            .offset(x: -70, y: -46)
                            .allowsHitTesting(false)
                    }
                }
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 12)
    }

    private func ringsInText(from now: Date, to date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return "Rings in \(days)d \(hours)h" }
        if hours > 0 { return "Rings in \(hours)h \(mins)m" }
        return mins == 0 ? "Rings in under a minute" : "Rings in \(mins)m"
    }

    // MARK: Challenges

    private var challenges: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Challenges")
                    .font(.wakie(22, .heavy))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("- Click to try it out")
                    .font(.wakie(15, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            ForEach(Array(Mission.allCases.enumerated()), id: \.element) { index, mission in
                Button {
                    practice = MissionRun(mission: mission, isPractice: true)
                } label: {
                    ChallengeBanner(mission: mission)
                        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -2 : 1.5))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Stats

    /// Plain read-only figures (no card or glass), so they don't look like buttons.
    private var statsRow: some View {
        HStack(spacing: 0) {
            StatCard(symbol: "flame.fill", tint: .orange, title: "Wake ups", value: "\(model.stats.wakeUps)", unit: "total")
            Rectangle()
                .fill(Theme.inkSecondary.opacity(0.3))
                .frame(width: 1)
                .padding(.vertical, 6)
            StatCard(symbol: "bolt.fill", tint: Theme.yellowDeep, title: "Avg time to wake", value: model.stats.averageText, unit: nil)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 4)
    }
}

/// Yellow brush banner with a mission's mascot and name.
struct ChallengeBanner: View {
    let mission: Mission

    var body: some View {
        HStack(spacing: 12) {
            MascotImage(mission: mission, size: 58)
                // The Pickie-Picky art sits a touch small and right of centre, so nudge it.
                .scaleEffect(mission == .pickiePicky ? 1.1 : 1)
                .offset(x: mission == .pickiePicky ? -6 : 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(mission.title)
                    .font(.wakie(24, .black))
                Text(mission.tagline)
                    .font(.wakie(12, .semibold))
                    .opacity(0.7)
            }
            .foregroundStyle(Color(hex: 0x1E1A3C))
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(mission.bannerColor)
                .offset(x: 1.5) // optically centre the triangle
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color(hex: 0x1E1A3C)))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(BrushBanner().fill(mission.bannerColor).shadow(color: mission.bannerColor.opacity(0.5), radius: 10, y: 6))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Try this mission")
    }
}

struct StatCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let unit: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(tint.gradient)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.wakie(12, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.wakie(26, .black))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit)
                            .font(.wakie(12, .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Big yellow "+" with soft rings pulsing out of it, so the main action is hard to miss.
struct AddAlarmButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tapped = false

    var body: some View {
        Button {
            tapped.toggle()
            action()
        } label: {
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<2, id: \.self) { ring in
                            let phase = (t / 1.8 + Double(ring) / 2).truncatingRemainder(dividingBy: 1)
                            Circle()
                                .stroke(Theme.yellow.opacity(0.7 * (1 - phase)), lineWidth: 3)
                                .scaleEffect(1 + phase * 0.55)
                        }
                    }
                    .frame(width: 64, height: 64)
                }
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Color(hex: 0x1E1A3C))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.yellow).shadow(color: Theme.yellowDeep.opacity(0.6), radius: 10, y: 4))
                    .phaseAnimator([1.0, 1.08, 1.0], trigger: reduceMotion ? 0 : 1) { content, scale in
                        content.scaleEffect(scale)
                    } animation: { _ in .easeInOut(duration: 0.5).delay(1.2) }
            }
            .frame(width: 90, height: 90)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: tapped)
        .accessibilityLabel("Add alarm")
    }
}

#Preview {
    HomeView()
        .environment(AppModel.shared)
}

#Preview("Alarm in another time zone") {
    let model = AppModel.shared
    model.alarms = [WakieAlarm(hour: 6, minute: 30, mission: .blahBlah,
                               timeZoneID: "America/New_York", placeName: "New York", placeFlag: "🇺🇸")]
    return HomeView()
        .environment(model)
}
