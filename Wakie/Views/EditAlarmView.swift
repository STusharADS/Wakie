//
//  EditAlarmView.swift
//  Wakie
//
//  Modal used to create or edit an alarm.
//

import SwiftUI

struct EditAlarmView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: WakieAlarm
    @State private var hourIndex: Int      // 0...11 -> 1...12
    @State private var minuteIndex: Int
    @State private var periodIndex: Int    // 0 = AM, 1 = PM
    @State private var confirmDelete = false
    @State private var isPickingSound = false
    @State private var isAddingCity = false
    let isNew: Bool

    private static let hourLabels = (1...12).map { String(format: "%02d", $0) }
    private static let minuteLabels = (0...59).map { String(format: "%02d", $0) }

    init(alarm: WakieAlarm, isNew: Bool) {
        _draft = State(initialValue: alarm)
        _hourIndex = State(initialValue: alarm.hour12 - 1)
        _minuteIndex = State(initialValue: alarm.minute)
        _periodIndex = State(initialValue: alarm.isPM ? 1 : 0)
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    timePicker
                    repeatSection
                    challengeSection
                    soundRow
                    snoozeCard
                    timeZoneCard
                    if !isNew {
                        deleteButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppBackground(showsBlobs: false))
        .presentationDragIndicator(.visible)
        .confirmationDialog("Delete this alarm?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Alarm", role: .destructive) {
                model.delete(draft.id)
                dismiss()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            CircleIconButton(systemName: "xmark") { dismiss() }
                .accessibilityLabel("Cancel")
            Spacer()
            Text(isNew ? "New Alarm" : "Edit Alarm")
                .font(.wakie(24, .heavy))
                .foregroundStyle(Theme.ink)
            Spacer()
            CircleIconButton(systemName: "checkmark", fill: Theme.yellow, foreground: Color(hex: 0x1E1A3C)) {
                save()
            }
            .accessibilityLabel("Save")
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 10)
    }

    /// The draft with the wheel selections applied.
    private var composedAlarm: WakieAlarm {
        var alarm = draft
        // 12 AM is hour 0 and 12 PM is hour 12.
        alarm.hour = (hourIndex + 1) % 12 + (periodIndex == 1 ? 12 : 0)
        alarm.minute = minuteIndex
        return alarm
    }

    private func save() {
        model.save(composedAlarm)
        dismiss()
    }

    // MARK: Time

    private var timePicker: some View {
        HStack(spacing: 8) {
            WheelColumn(labels: Self.hourLabels, selection: $hourIndex, accessibilityName: "Hour",
                        width: 108, height: 104, itemHeight: 72, fontSize: 56)
            Text(":")
                .font(.wakie(44, .black))
                .foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            WheelColumn(labels: Self.minuteLabels, selection: $minuteIndex, accessibilityName: "Minute",
                        width: 108, height: 104, itemHeight: 72, fontSize: 56)
            WheelColumn(labels: ["AM", "PM"], selection: $periodIndex, loops: false, accessibilityName: "AM or PM",
                        width: 70, height: 64, itemHeight: 40, fontSize: 22)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            SparkleLines(size: 30)
                .rotationEffect(.degrees(-40))
                .offset(x: -6, y: -14)
        }
        .padding(.top, 14)
    }

    // MARK: Time zone

    /// Selection key: "local" or a world-clock city's id.
    private var zoneSelection: Binding<String> {
        Binding(
            get: {
                // An alarm on the phone's own clock shows as the matching city (e.g. Naples).
                guard draft.timeZoneID != nil else { return LocalPlace.matchingCity?.id ?? "local" }
                return model.cities.first { $0.timeZoneID == draft.timeZoneID && $0.name == draft.placeName }?.id ?? "local"
            },
            set: { key in
                if let city = model.cities.first(where: { $0.id == key }) {
                    draft.timeZoneID = city.timeZoneID
                    draft.placeName = city.name
                    draft.placeFlag = city.flag
                } else {
                    draft.timeZoneID = nil
                    draft.placeName = nil
                    draft.placeFlag = nil
                }
            }
        )
    }

    /// Card below Snooze for choosing which place's clock the alarm follows.
    private var timeZoneCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Time zone")
                    .font(.wakie(16, .bold))
                    .foregroundStyle(Theme.ink)
                Text(composedAlarm.isLocal
                     ? "Uses your phone's time."
                     : "Rings at \(composedAlarm.localTimeText()) your time.")
                    .font(.wakie(12, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            // Centred vertically against both lines of text.
            zonePicker
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .wakieCard(radius: 18)
    }

    /// Menu capsule listing your place plus every World Clock city.
    private var zonePicker: some View {
        Menu {
            Picker("Time zone", selection: zoneSelection) {
                // Only needed when none of the World Clock cities is where you are.
                if LocalPlace.matchingCity == nil {
                    Text("📍 My time").tag("local")
                }
                ForEach(model.cities) { city in
                    Text("\(city.flag) \(city.name)").tag(city.id)
                }
            }
            Divider()
            // Same flow as the World Clock tab; the new city is also added there.
            Button("Add a City…", systemImage: "plus.circle") {
                isAddingCity = true
            }
        } label: {
            HStack(spacing: 6) {
                Text(draft.placeLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .black))
            }
            .font(.wakie(15, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Capsule().fill(Theme.lavenderPill))
        }
        .accessibilityLabel("Alarm time zone, \(draft.placeLabel)")
        .sheet(isPresented: $isAddingCity) {
            AddCitySheet { city in
                // Use the city just added for this alarm.
                zoneSelection.wrappedValue = city.id
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: Repeat

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Repeat")
            HStack(spacing: 0) {
                ForEach(Weekday.allCases) { day in
                    let isOn = draft.repeatDays.contains(day)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            if isOn { draft.repeatDays.remove(day) } else { draft.repeatDays.insert(day) }
                        }
                    } label: {
                        Text(day.initial)
                            .font(.wakie(16, .heavy))
                            .foregroundStyle(isOn ? Color(hex: 0x1E1A3C) : Theme.ink)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(isOn ? AnyShapeStyle(Theme.yellow) : AnyShapeStyle(Theme.card))
                                    .shadow(color: isOn ? Theme.yellowDeep.opacity(0.4) : Theme.shadow, radius: 6, y: 3)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(day.fullName)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Text(draft.repeatDays.isEmpty ? "Rings once" : draft.repeatText)
                .font(.wakie(12, .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    // MARK: Challenge

    private var challengeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Challenge")
            HStack(spacing: 12) {
                ForEach(Mission.allCases) { mission in
                    MissionTile(mission: mission, isSelected: draft.mission == mission) {
                        withAnimation(.snappy(duration: 0.2)) { draft.mission = mission }
                    }
                }
            }
        }
    }

    // MARK: Sound & snooze

    private var soundRow: some View {
        Button {
            isPickingSound = true
        } label: {
            HStack {
                Text("Sound")
                    .font(.wakie(16, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(draft.soundTitle)
                    .font(.wakie(15, .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .wakieCard(radius: 18)
        }
        .buttonStyle(PressableStyle())
        .sheet(isPresented: $isPickingSound) {
            SoundPickerSheet(selection: $draft.soundFile)
                .presentationDetents([.medium, .large])
        }
    }

    private var snoozeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Snooze")
                    .font(.wakie(16, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(draft.snoozeMinutes == 0 ? "Off" : "\(draft.snoozeMinutes) min")
                    .font(.wakie(15, .heavy))
                    .foregroundStyle(draft.snoozeMinutes == 0 ? Theme.inkSecondary : Theme.purple)
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(
                    get: { Double(draft.snoozeMinutes) },
                    set: { draft.snoozeMinutes = Int($0.rounded()) }
                ),
                in: 0...5,
                step: 1
            ) {
                Text("Snooze length")
            } minimumValueLabel: {
                Text("0").font(.wakie(12, .semibold)).foregroundStyle(Theme.inkSecondary)
            } maximumValueLabel: {
                Text("5").font(.wakie(12, .semibold)).foregroundStyle(Theme.inkSecondary)
            }
            .tint(Theme.purple)
            Text(draft.snoozeMinutes == 0 ? "No snooze button. You have to do the mission." : "You can snooze once, then the mission is the only way out.")
                .font(.wakie(12, .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .wakieCard(radius: 18)
    }

    private var deleteButton: some View {
        Button {
            confirmDelete = true
        } label: {
            Text("Delete Alarm")
                .font(.wakie(18, .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.dangerLight, Theme.danger], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Theme.danger.opacity(0.4), radius: 10, y: 6)
                )
        }
        .buttonStyle(PressableStyle())
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }
}

/// A scrollable drum for picking one value, styled as the dark time boxes in the design.
struct WheelColumn: View {
    let labels: [String]
    @Binding var selection: Int
    var loops = true
    let accessibilityName: String
    let width: CGFloat
    let height: CGFloat
    let itemHeight: CGFloat
    let fontSize: CGFloat

    @State private var scrolledID: Int?

    /// Looping wheels repeat their labels many times and start in the middle,
    /// so the person can keep scrolling in either direction.
    private var repeatCount: Int { loops ? 100 : 1 }

    init(labels: [String], selection: Binding<Int>, loops: Bool = true, accessibilityName: String,
         width: CGFloat, height: CGFloat, itemHeight: CGFloat, fontSize: CGFloat) {
        self.labels = labels
        _selection = selection
        self.loops = loops
        self.accessibilityName = accessibilityName
        self.width = width
        self.height = height
        self.itemHeight = itemHeight
        self.fontSize = fontSize
        let base = loops ? labels.count * 50 : 0 // middle of the 100 repeats
        _scrolledID = State(initialValue: base + selection.wrappedValue)
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<(labels.count * repeatCount), id: \.self) { index in
                    Text(labels[index % labels.count])
                        .font(.wakie(fontSize, .black))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: width, height: itemHeight)
                        .scrollTransition(axis: .vertical) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.25)
                                .scaleEffect(phase.isIdentity ? 1 : 0.7)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledID, anchor: .center)
        .contentMargins(.vertical, (height - itemHeight) / 2, for: .scrollContent)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3A3458), Theme.timeBox], startPoint: .top, endPoint: .bottom))
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.timeBox.opacity(0.35), radius: 10, y: 6)
        .onChange(of: scrolledID) { _, newValue in
            if let newValue { selection = newValue % labels.count }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityRepresentation {
            Picker(accessibilityName, selection: $selection) {
                ForEach(labels.indices, id: \.self) { index in
                    Text(labels[index]).tag(index)
                }
            }
        }
    }
}

#Preview {
    EditAlarmView(alarm: WakieAlarm(hour: 5, minute: 0, repeatDays: [.tuesday, .wednesday]), isNew: false)
        .environment(AppModel.shared)
}
