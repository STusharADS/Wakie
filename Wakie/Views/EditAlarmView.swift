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
    @State private var isTypingTime = false
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
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Tapping a number wheel opens a keypad; scrolling still works as before.
                // Tall enough to show the values above and below, like the Clock app.
                WheelColumn(labels: Self.hourLabels, selection: $hourIndex, accessibilityName: "Hour",
                            width: 104, height: 190, itemHeight: 62, fontSize: 50,
                            onTap: { isTypingTime = true })
                Text(":")
                    .font(.wakie(44, .black))
                    .foregroundStyle(Theme.ink)
                    .accessibilityHidden(true)
                WheelColumn(labels: Self.minuteLabels, selection: $minuteIndex, accessibilityName: "Minute",
                            width: 104, height: 190, itemHeight: 62, fontSize: 50,
                            onTap: { isTypingTime = true })
                // Tapping AM/PM simply flips it.
                WheelColumn(labels: ["AM", "PM"], selection: $periodIndex, loops: false, accessibilityName: "AM or PM",
                            width: 70, height: 130, itemHeight: 44, fontSize: 22,
                            onTap: { periodIndex = 1 - periodIndex })
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                SparkleLines(size: 30)
                    .rotationEffect(.degrees(-40))
                    .offset(x: -6, y: -14)
            }
        }
        .padding(.top, 14)
        .sheet(isPresented: $isTypingTime) {
            TimeEntrySheet(hour: hourIndex + 1, minute: minuteIndex, isPM: periodIndex == 1) { hour, minute, isPM in
                hourIndex = hour - 1
                minuteIndex = minute
                periodIndex = isPM ? 1 : 0
            }
            .presentationDetents([.height(320)])
        }
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
                Text("Ringtone")
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
            if model.easyTimePicking {
                HorizontalWheelPicker(values: Array(0...5), selection: $draft.snoozeMinutes,
                                      accessibilityName: "Snooze length",
                                      label: { $0 == 0 ? "Off" : "\($0)m" })
            } else {
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
                .sensoryFeedback(.selection, trigger: draft.snoozeMinutes)
            }
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
    var onTap: (() -> Void)?

    @State private var scrolledID: Int?

    /// Looping wheels repeat their labels many times and start in the middle,
    /// so the person can keep scrolling in either direction.
    private var repeatCount: Int { loops ? 100 : 1 }

    init(labels: [String], selection: Binding<Int>, loops: Bool = true, accessibilityName: String,
         width: CGFloat, height: CGFloat, itemHeight: CGFloat, fontSize: CGFloat, onTap: (() -> Void)? = nil) {
        self.onTap = onTap
        self.labels = labels
        _selection = selection
        self.loops = loops
        self.accessibilityName = accessibilityName
        self.width = width
        self.height = height
        self.itemHeight = itemHeight
        self.fontSize = fontSize
    }

    /// Where the wheel starts: the selected value, in the middle of the repeats for looping wheels.
    private var initialID: Int {
        (loops ? labels.count * 50 : 0) + selection
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
                            // Values above and below stay visible but dimmer and smaller.
                            content
                                .opacity(phase.isIdentity ? 1 : 0.4)
                                .scaleEffect(phase.isIdentity ? 1 : 0.78)
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
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x3A3458), Theme.timeBox], startPoint: .top, endPoint: .bottom))
                // Selection band behind the chosen value.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(height: itemHeight)
                    .padding(.horizontal, 6)
            }
        )
        // Fade the top and bottom edges so it reads as a rolling drum.
        .mask(
            LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                   .init(color: .black, location: 0.3),
                                   .init(color: .black, location: 0.7),
                                   .init(color: .black.opacity(0.35), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.timeBox.opacity(0.35), radius: 10, y: 6)
        // Position once laid out; setting it up front lands one row off on tall wheels.
        .onAppear { if scrolledID == nil { scrolledID = initialID } }
        .onChange(of: scrolledID) { _, newValue in
            if let newValue { selection = newValue % labels.count }
        }
        // Follow changes made elsewhere (typed time, AM/PM tap) by scrolling to the nearest match.
        .onChange(of: selection) { _, newValue in
            guard let current = scrolledID, current % labels.count != newValue else { return }
            let base = current - current % labels.count
            withAnimation(.snappy) { scrolledID = base + newValue }
        }
        .onTapGesture { onTap?() }
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

/// Keypad entry for the alarm time: hour and minute boxes plus an AM/PM switch.
struct TimeEntrySheet: View {
    let onDone: (_ hour: Int, _ minute: Int, _ isPM: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hourText: String
    @State private var minuteText: String
    @State private var isPM: Bool
    @FocusState private var focused: Field?

    private enum Field { case hour, minute }

    init(hour: Int, minute: Int, isPM: Bool, onDone: @escaping (_ hour: Int, _ minute: Int, _ isPM: Bool) -> Void) {
        self.onDone = onDone
        _hourText = State(initialValue: String(hour))
        _minuteText = State(initialValue: String(format: "%02d", minute))
        _isPM = State(initialValue: isPM)
    }

    private var hour: Int? { Int(hourText).flatMap { (1...12).contains($0) ? $0 : nil } }
    private var minute: Int? { Int(minuteText).flatMap { (0...59).contains($0) ? $0 : nil } }

    var body: some View {
        VStack(spacing: 18) {
            Text("Type a time")
                .font(.wakie(20, .black))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                numberField($hourText, field: .hour, placeholder: "7", isValid: hour != nil)
                Text(":")
                    .font(.wakie(44, .black))
                    .foregroundStyle(Theme.ink)
                numberField($minuteText, field: .minute, placeholder: "00", isValid: minute != nil)
                Picker("AM or PM", selection: $isPM) {
                    Text("AM").tag(false)
                    Text("PM").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            Button {
                guard let hour, let minute else { return }
                onDone(hour, minute, isPM)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } label: {
                Text("Set time")
                    .font(.wakie(17, .heavy))
                    .foregroundStyle(Color(hex: 0x1E1A3C))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(Theme.yellow))
            }
            .buttonStyle(PressableStyle())
            .disabled(hour == nil || minute == nil)
            .opacity(hour == nil || minute == nil ? 0.5 : 1)
        }
        .padding(24)
        .onAppear { focused = .hour }
        .onChange(of: hourText) { _, text in
            // Jump to minutes once the hour is clearly complete.
            if text.count == 2 || (text.count == 1 && (Int(text) ?? 0) > 1) { focused = .minute }
        }
        .sensoryFeedback(.selection, trigger: isPM)
    }

    private func numberField(_ text: Binding<String>, field: Field, placeholder: String, isValid: Bool) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .focused($focused, equals: field)
            .multilineTextAlignment(.center)
            .font(.wakie(44, .black))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 92, height: 76)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.timeBox))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isValid ? Theme.yellow.opacity(focused == field ? 1 : 0) : Theme.danger, lineWidth: 3)
            )
            .onChange(of: text.wrappedValue) { _, new in
                // Digits only, at most two.
                let digits = String(new.filter(\.isNumber).prefix(2))
                if digits != new { text.wrappedValue = digits }
            }
            .accessibilityLabel(field == .hour ? "Hour" : "Minute")
    }
}

#Preview {
    EditAlarmView(alarm: WakieAlarm(hour: 5, minute: 0, repeatDays: [.tuesday, .wednesday]), isNew: false)
        .environment(AppModel.shared)
}
