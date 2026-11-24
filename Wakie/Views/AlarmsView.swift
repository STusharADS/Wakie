//
//  AlarmsView.swift
//  Wakie
//

import SwiftUI

struct AlarmsView: View {
    @Environment(AppModel.self) private var model
    @State private var isEditing = false
    @State private var editingAlarm: WakieAlarm?
    @State private var isCreating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.alarmsDenied {
                    permissionBanner
                }
                if model.alarms.isEmpty {
                    emptyState
                } else {
                    ForEach(model.sortedAlarms) { alarm in
                        AlarmCard(
                            alarm: alarm,
                            isEditing: isEditing,
                            onToggle: { model.setEnabled($0, for: alarm.id) },
                            onDelete: { withAnimation(.snappy) { model.delete(alarm.id) } }
                        )
                        .onTapGesture { editingAlarm = alarm }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .sheet(item: $editingAlarm) { alarm in
            EditAlarmView(alarm: alarm, isNew: false)
        }
        .sheet(isPresented: $isCreating) {
            EditAlarmView(alarm: WakieAlarm(), isNew: true)
        }
        .onChange(of: model.alarms.isEmpty) { _, empty in
            if empty { isEditing = false }
        }
    }

    private var header: some View {
        TabHeader(isEditing: $isEditing, showsEdit: !model.alarms.isEmpty, addLabel: "Add alarm") {
            isCreating = true
        } title: {
            ScreenTitle(text: "Alarms")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            MascotImage(mission: .shakyShaky, size: 110)
            Text("No alarms yet")
                .font(.wakie(22, .black))
                .foregroundStyle(Theme.ink)
            Text("Tap + to set an alarm and pick a mission that gets you out of bed.")
                .font(.wakie(14, .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .wakieCard()
        .padding(.top, 20)
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            Text("Wakie isn't allowed to schedule alarms. Turn on Alarms for Wakie in Settings.")
                .font(.wakie(13, .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open", destination: url)
                    .font(.wakie(13, .bold))
            }
        }
        .padding(14)
        .wakieCard(radius: 20)
    }
}

struct AlarmCard: View {
    let alarm: WakieAlarm
    let isEditing: Bool
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MascotImage(mission: alarm.mission, size: 78)
                .padding(.leading, -6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(alarm.timeText)
                        .font(.wakie(38, .black))
                    Text(alarm.periodText)
                        .font(.wakie(20, .heavy))
                }
                .foregroundStyle(Theme.ink)
                Text(alarm.subtitle)
                    .font(.wakie(13, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    PlaceButton(alarm: alarm)
                    if !alarm.isLocal {
                        Text("\(alarm.localTimeText()) here")
                            .font(.wakie(11, .semibold))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.top, 4)
            }
            .opacity(alarm.isEnabled ? 1 : 0.55)
            Spacer(minLength: 0)
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.danger))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete alarm")
                .transition(.scale.combined(with: .opacity))
            } else {
                PillSwitch(isOn: Binding(get: { alarm.isEnabled }, set: onToggle))
                    .accessibilityLabel("Alarm \(alarm.timeText) \(alarm.periodText)")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .wakieCard(radius: 30)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityHint("Double tap to edit")
    }
}

/// Capsule naming the alarm's place. Tapping it shows the ring time in every world-clock city.
struct PlaceButton: View {
    let alarm: WakieAlarm
    @State private var showingZones = false

    var body: some View {
        Button {
            showingZones = true
        } label: {
            HStack(spacing: 4) {
                Text(alarm.placeLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
            }
            .font(.wakie(11, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(Theme.lavenderPill))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Time zone \(alarm.placeLabel). Show times around the world")
        .popover(isPresented: $showingZones) {
            AlarmZonesView(alarm: alarm)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// When an alarm rings, what time is it in each world-clock city?
struct AlarmZonesView: View {
    @Environment(AppModel.self) private var model
    let alarm: WakieAlarm

    private struct Row: Identifiable {
        let id: String
        let flag: String
        let name: String
        let timeZone: TimeZone
        let isAlarmPlace: Bool
    }

    private var rows: [Row] {
        var rows = [Row(id: "local", flag: LocalPlace.flag, name: "\(LocalPlace.name) (you)",
                        timeZone: .current, isAlarmPlace: alarm.timeZoneID == nil)]
        // The local row already covers the city you're in.
        for city in model.cities where city.id != LocalPlace.matchingCity?.id {
            rows.append(Row(id: city.id, flag: city.flag, name: city.name, timeZone: city.timeZone,
                            isAlarmPlace: city.timeZoneID == alarm.timeZoneID && city.name == alarm.placeName))
        }
        return rows
    }

    var body: some View {
        let fire = alarm.nextFireDate() ?? .now
        VStack(alignment: .leading, spacing: 10) {
            Text("When it rings")
                .font(.wakie(15, .heavy))
                .foregroundStyle(Theme.ink)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.flag)
                    Text(row.name)
                        .font(.wakie(14, row.isAlarmPlace ? .heavy : .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 16)
                    Text(fire.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: row.timeZone)))
                        .font(.wakie(14, .bold))
                        .monospacedDigit()
                        .foregroundStyle(row.isAlarmPlace ? Theme.purple : Theme.ink)
                    Text(dayNote(fire, in: row.timeZone))
                        .font(.wakie(11, .semibold))
                        .foregroundStyle(.gray)
                        .frame(width: 30, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 260)
    }

    /// "-1d" / "+1d" when the ring time falls on another calendar day there.
    private func dayNote(_ date: Date, in zone: TimeZone) -> String {
        var there = Calendar.current
        there.timeZone = zone
        var alarmCal = Calendar.current
        alarmCal.timeZone = alarm.timeZone
        let a = there.dateComponents([.year, .month, .day], from: date)
        let b = alarmCal.dateComponents([.year, .month, .day], from: date)
        guard let da = there.date(from: a), let db = there.date(from: b) else { return "" }
        let diff = Calendar.current.dateComponents([.day], from: db, to: da).day ?? 0
        return diff == 0 ? "" : (diff > 0 ? "+\(diff)d" : "\(diff)d")
    }
}

/// The system switch, which renders with Liquid Glass, tinted purple.
struct PillSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Theme.purple)
            .fixedSize()
    }
}

#Preview {
    let model = AppModel.shared
    model.alarms = [
        WakieAlarm(hour: 5, minute: 0, repeatDays: [.tuesday, .wednesday], mission: .shakyShaky),
        WakieAlarm(hour: 6, minute: 10, repeatDays: [.monday], mission: .pickiePicky, isEnabled: false),
        WakieAlarm(hour: 8, minute: 15, mission: .blahBlah, timeZoneID: "America/New_York", placeName: "New York", placeFlag: "🇺🇸"),
    ]
    return AlarmsView()
        .environment(model)
}
