//
//  SiriIntents.swift
//  Wakie
//
//  Siri / Shortcuts support: set, edit and delete Wakie alarms by voice.
//  People can say as much or as little as they like ("Set a Wakie alarm for 6 PM
//  every Tuesday and Friday in New York time"). Siri asks follow-up questions for
//  anything required that wasn't said (the time and the challenge); repeat days
//  and time zone are optional and default to a one-time alarm on the phone's clock.
//

import AppIntents
import Foundation

// MARK: - Challenge as a Siri-understandable value

nonisolated extension Mission: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Challenge"

    static let caseDisplayRepresentations: [Mission: DisplayRepresentation] = [
        .shakyShaky: DisplayRepresentation(title: "Shaky-Shaky", subtitle: "Dance to stop the alarm",
                                           synonyms: ["Shaky Shaky", "Shakie Shaky", "Shakey Shakey", "Shaky", "shake", "dance", "dancing"]),
        .pickiePicky: DisplayRepresentation(title: "Pickie-Picky", subtitle: "Find an item and show it",
                                            synonyms: ["Pickie Picky", "Picky Picky", "Picky", "Pickie", "find", "object"]),
        .blahBlah: DisplayRepresentation(title: "Blah-Blah", subtitle: "Talk out loud",
                                         synonyms: ["Blah Blah", "Blah", "talk", "talking", "speak"]),
    ]
}

// MARK: - Repeat days

nonisolated extension Weekday: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Day"

    static let caseDisplayRepresentations: [Weekday: DisplayRepresentation] = [
        .monday: DisplayRepresentation(title: "Monday", synonyms: ["Mondays", "Mon"]),
        .tuesday: DisplayRepresentation(title: "Tuesday", synonyms: ["Tuesdays", "Tue", "Tues"]),
        .wednesday: DisplayRepresentation(title: "Wednesday", synonyms: ["Wednesdays", "Wed"]),
        .thursday: DisplayRepresentation(title: "Thursday", synonyms: ["Thursdays", "Thu", "Thurs"]),
        .friday: DisplayRepresentation(title: "Friday", synonyms: ["Fridays", "Fri"]),
        .saturday: DisplayRepresentation(title: "Saturday", synonyms: ["Saturdays", "Sat"]),
        .sunday: DisplayRepresentation(title: "Sunday", synonyms: ["Sundays", "Sun"]),
    ]
}

// MARK: - Time zone places Siri can understand ("New York time")

nonisolated struct AlarmPlaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Time Zone"
    static let defaultQuery = AlarmPlaceQuery()

    /// "<time zone>|<place name>", so two places sharing a zone (Naples, Rome) stay distinct.
    var id: String { "\(timeZoneID)|\(name)" }
    let name: String
    let flag: String
    let timeZoneID: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(flag) \(timeZoneID)")
    }
}

nonisolated struct AlarmPlaceQuery: EntityStringQuery {
    /// Well-known names that aren't a time zone's own city, e.g. "San Francisco" or "Eastern".
    private static let aliases: [(name: String, flag: String, timeZoneID: String)] = [
        ("San Francisco", "🇺🇸", "America/Los_Angeles"), ("Seattle", "🇺🇸", "America/Los_Angeles"),
        ("Pacific", "🇺🇸", "America/Los_Angeles"), ("California", "🇺🇸", "America/Los_Angeles"),
        ("Eastern", "🇺🇸", "America/New_York"), ("Washington", "🇺🇸", "America/New_York"),
        ("Boston", "🇺🇸", "America/New_York"), ("Miami", "🇺🇸", "America/New_York"),
        ("Central", "🇺🇸", "America/Chicago"), ("Dallas", "🇺🇸", "America/Chicago"), ("Houston", "🇺🇸", "America/Chicago"),
        ("Mountain", "🇺🇸", "America/Denver"),
        ("India", "🇮🇳", "Asia/Kolkata"), ("Delhi", "🇮🇳", "Asia/Kolkata"), ("Mumbai", "🇮🇳", "Asia/Kolkata"),
        ("Bangalore", "🇮🇳", "Asia/Kolkata"), ("Chennai", "🇮🇳", "Asia/Kolkata"),
        ("Japan", "🇯🇵", "Asia/Tokyo"), ("China", "🇨🇳", "Asia/Shanghai"), ("Beijing", "🇨🇳", "Asia/Shanghai"),
        ("UK", "🇬🇧", "Europe/London"), ("England", "🇬🇧", "Europe/London"),
        ("Germany", "🇩🇪", "Europe/Berlin"), ("France", "🇫🇷", "Europe/Paris"), ("Italy", "🇮🇹", "Europe/Rome"),
        ("Spain", "🇪🇸", "Europe/Madrid"), ("UAE", "🇦🇪", "Asia/Dubai"), ("Australia", "🇦🇺", "Australia/Sydney"),
        ("GMT", "🌍", "GMT"), ("UTC", "🌍", "GMT"),
    ]

    /// Popular places offered as suggestions and spoken-phrase options.
    private static let popular = ["New York", "Los Angeles", "Chicago", "London", "Paris", "Berlin", "Rome",
                                  "Dubai", "Kolkata", "Singapore", "Tokyo", "Sydney", "Toronto"]

    /// The person's World Clock cities first, then aliases, then every city with its own time zone.
    @MainActor private static func allPlaces() -> [AlarmPlaceEntity] {
        let saved = AppModel.shared.cities
        var places = saved.map { AlarmPlaceEntity(name: $0.name, flag: $0.flag, timeZoneID: $0.timeZoneID) }
        places += aliases.map { AlarmPlaceEntity(name: $0.name, flag: $0.flag, timeZoneID: $0.timeZoneID) }
        for id in TimeZone.knownTimeZoneIdentifiers {
            let flag = (saved + WorldCity.defaults).first { $0.timeZoneID == id }?.flag
                ?? aliases.first { $0.timeZoneID == id }?.flag ?? "🌍"
            places.append(AlarmPlaceEntity(name: WorldCity.cityName(fromTimeZoneID: id), flag: flag, timeZoneID: id))
        }
        // Keep the first place for each name (saved cities win).
        var seen = Set<String>()
        return places.filter { seen.insert($0.name.lowercased()).inserted }
    }

    func entities(for identifiers: [String]) async throws -> [AlarmPlaceEntity] {
        await MainActor.run { Self.allPlaces().filter { identifiers.contains($0.id) } }
    }

    func entities(matching string: String) async throws -> [AlarmPlaceEntity] {
        // "New York time" / "New York's time" -> "new york"
        var query = string.lowercased()
        for suffix in [" time zone", " timezone", " time", "'s"] where query.hasSuffix(suffix) {
            query.removeLast(suffix.count)
        }
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return [] }
        return await MainActor.run {
            let places = Self.allPlaces()
            let exact = places.filter { $0.name.lowercased() == name }
            return exact.isEmpty ? places.filter { $0.name.lowercased().contains(name) } : exact
        }
    }

    func suggestedEntities() async throws -> [AlarmPlaceEntity] {
        await MainActor.run {
            let places = Self.allPlaces()
            let saved = Set(AppModel.shared.cities.map(\.name))
            return places.filter { saved.contains($0.name) || Self.popular.contains($0.name) }
        }
    }
}

// MARK: - Alarms as entities Siri can refer to

nonisolated struct AlarmEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Alarm"
    static let defaultQuery = AlarmEntityQuery()

    let id: UUID
    let time: String
    let details: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(time)", subtitle: "\(details)")
    }

    init(_ alarm: WakieAlarm) {
        id = alarm.id
        time = "\(alarm.timeText) \(alarm.periodText)"
        details = alarm.subtitle + (alarm.isEnabled ? "" : " · Off")
    }
}

nonisolated struct AlarmEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AlarmEntity] {
        await MainActor.run {
            AppModel.shared.alarms.filter { identifiers.contains($0.id) }.map(AlarmEntity.init)
        }
    }

    func suggestedEntities() async throws -> [AlarmEntity] {
        await MainActor.run { AppModel.shared.sortedAlarms.map(AlarmEntity.init) }
    }
}

/// Your alarms, in time order, for Siri to choose from.
private nonisolated func alarmChoices() async -> [AlarmEntity] {
    await MainActor.run { AppModel.shared.sortedAlarms.map(AlarmEntity.init) }
}

/// The alarm times as one phrase Siri can read out, like "7:00 AM, 8:30 AM, or 9:00 AM".
private nonisolated func spokenList(of alarms: [AlarmEntity]) -> String {
    alarms.map(\.time).formatted(.list(type: .or))
}

/// Hour and minute from a time Siri understood.
private nonisolated func clockParts(_ date: Date) -> (hour: Int, minute: Int) {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 7, parts.minute ?? 0)
}

// MARK: - Set an alarm

struct CreateAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Set a Wakie Alarm"
    static let description = IntentDescription("Sets an alarm that you turn off by completing a challenge.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Time", description: "The time the alarm rings, like 6 PM.", kind: .time,
               requestValueDialog: IntentDialog("What time should I set the alarm for?"))
    var time: Date

    // Siri asks for a challenge by offering the choices, which uses the disambiguation
    // dialog. Naming every option here means Siri reads them out loud.
    @Parameter(title: "Challenge", description: "The challenge that turns the alarm off: Shaky-Shaky, Pickie-Picky or Blah-Blah.",
               requestValueDialog: IntentDialog("Which challenge: Shaky-Shaky, Pickie-Picky, or Blah-Blah?"),
               requestDisambiguationDialog: IntentDialog("Which challenge: Shaky-Shaky, Pickie-Picky, or Blah-Blah?"))
    var mission: Mission

    @Parameter(title: "Repeat On", description: "Days the alarm repeats, like every Tuesday and Friday. Leave empty for a one-time alarm.")
    var days: [Weekday]?

    @Parameter(title: "Time Zone", description: "A city or region whose local time the alarm uses, like New York. Leave empty to use the phone's own time.")
    var place: AlarmPlaceEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Set an alarm for \(\.$time) with \(\.$mission)") {
            \.$days
            \.$place
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (hour, minute) = clockParts(time)
        var alarm = WakieAlarm(hour: hour, minute: minute, mission: mission)
        alarm.repeatDays = Set(days ?? [])
        // The spoken time is read as a wall-clock time in the named place.
        if let place, place.timeZoneID != TimeZone.current.identifier {
            alarm.timeZoneID = place.timeZoneID
            alarm.placeName = place.name
            alarm.placeFlag = place.flag
        }
        let scheduled = await AppModel.shared.saveAndSchedule(alarm)
        guard scheduled else {
            return .result(dialog: "I saved the alarm, but Wakie isn't allowed to ring alarms yet. Open Wakie to allow it.")
        }
        let placeText = alarm.timeZoneID == nil ? "" : " \(alarm.placeName ?? "") time"
        let repeatText = alarm.isRepeating ? ", \(alarm.repeatText.lowercased())" : ""
        return .result(dialog: "Done! Your \(alarm.timeText) \(alarm.periodText)\(placeText) \(mission.title) alarm is set\(repeatText).")
    }
}

// MARK: - Edit an alarm

struct EditAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Change a Wakie Alarm"
    static let description = IntentDescription("Changes the time or challenge of one of your alarms.")
    static let supportedModes: IntentModes = .background

    /// Optional so `perform()` can ask which alarm itself, reading the times out loud.
    @Parameter(title: "Alarm")
    var alarm: AlarmEntity?

    @Parameter(title: "New Time", kind: .time)
    var time: Date?

    @Parameter(title: "New Challenge")
    var mission: Mission?

    static var parameterSummary: some ParameterSummary {
        Summary("Change \(\.$alarm)") {
            \.$time
            \.$mission
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var chosen = alarm
        if chosen == nil {
            let choices = await alarmChoices()
            switch choices.count {
            case 0: return .result(dialog: "You don't have any Wakie alarms to change.")
            case 1: chosen = choices[0]
            default:
                chosen = try await $alarm.requestDisambiguation(
                    among: choices,
                    dialog: IntentDialog("Which alarm do you want to change? \(spokenList(of: choices))?")
                )
            }
        }
        guard let chosen,
              var stored = await MainActor.run(body: { AppModel.shared.alarms.first { $0.id == chosen.id } }) else {
            return .result(dialog: "I couldn't find that alarm.")
        }
        // If nothing to change was said, ask for the new time.
        var newTime = time
        if newTime == nil && mission == nil {
            newTime = try await $time.requestValue(IntentDialog("What time should it ring instead?"))
        }
        if let newTime {
            (stored.hour, stored.minute) = clockParts(newTime)
        }
        if let mission { stored.mission = mission }
        let updated = stored
        await AppModel.shared.saveAndSchedule(updated)
        return .result(dialog: "Updated. It now rings at \(updated.timeText) \(updated.periodText) with \(updated.mission.title).")
    }
}

// MARK: - Delete an alarm

struct DeleteAlarmIntent: AppIntent {
    static let title: LocalizedStringResource = "Delete a Wakie Alarm"
    static let description = IntentDescription("Deletes one of your alarms.")
    static let supportedModes: IntentModes = .background

    /// Optional so `perform()` can ask which alarm itself, reading the times out loud.
    @Parameter(title: "Alarm")
    var alarm: AlarmEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Delete \(\.$alarm)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var chosen = alarm
        if chosen == nil {
            let choices = await alarmChoices()
            switch choices.count {
            case 0: return .result(dialog: "You don't have any Wakie alarms to delete.")
            case 1: chosen = choices[0]
            default:
                chosen = try await $alarm.requestDisambiguation(
                    among: choices,
                    dialog: IntentDialog("Which alarm do you want to delete? \(spokenList(of: choices))?")
                )
            }
        }
        guard let chosen else { return .result(dialog: "I couldn't find that alarm.") }
        // Deleting can't be undone, so confirm first.
        try await requestConfirmation(
            actionName: .custom(acceptLabel: "Delete", acceptAlternatives: ["Yes", "Remove"], denyLabel: "Keep", denyAlternatives: ["No"], destructive: true),
            dialog: IntentDialog("Delete your \(chosen.time) alarm?")
        )
        let id = chosen.id
        await MainActor.run { AppModel.shared.delete(id) }
        return .result(dialog: "Deleted your \(chosen.time) alarm.")
    }
}

// MARK: - Siri phrases

struct WakieShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateAlarmIntent(),
            phrases: [
                "Set an alarm in \(.applicationName)",
                "Set a \(.applicationName) alarm",
                "Wake me up with \(.applicationName)",
                "Set a \(\.$mission) alarm in \(.applicationName)",
                "Create a \(.applicationName) alarm",
                "Make a \(.applicationName) alarm",
                "Add a \(.applicationName) alarm",
                "New \(.applicationName) alarm",
                "Set an alarm with \(.applicationName)",
                "Set my \(.applicationName) alarm",
                "\(.applicationName) wake me up",
                "Set a \(.applicationName) alarm with \(\.$mission)",
                "Set a \(.applicationName) alarm for \(\.$mission)",
                "Wake me up with \(\.$mission) in \(.applicationName)",
                "Create a \(\.$mission) alarm in \(.applicationName)",
                "Set a \(.applicationName) alarm in \(\.$place) time",
                "Set a \(.applicationName) alarm for \(\.$place) time",
            ],
            shortTitle: "Set Alarm",
            systemImageName: "alarm"
        )
        AppShortcut(
            intent: EditAlarmIntent(),
            phrases: [
                "Change my \(.applicationName) alarm",
                "Edit an alarm in \(.applicationName)",
                "Edit my \(.applicationName) alarm",
                "Update my \(.applicationName) alarm",
                "Move my \(.applicationName) alarm",
                "Reschedule my \(.applicationName) alarm",
                "Change an alarm in \(.applicationName)",
                "Change \(\.$alarm) in \(.applicationName)",
            ],
            shortTitle: "Change Alarm",
            systemImageName: "pencil"
        )
        AppShortcut(
            intent: DeleteAlarmIntent(),
            phrases: [
                "Delete a \(.applicationName) alarm",
                "Remove an alarm in \(.applicationName)",
                "Delete my \(.applicationName) alarm",
                "Remove my \(.applicationName) alarm",
                "Cancel my \(.applicationName) alarm",
                "Get rid of my \(.applicationName) alarm",
                "Delete \(\.$alarm) in \(.applicationName)",
            ],
            shortTitle: "Delete Alarm",
            systemImageName: "trash"
        )
    }
}

// MARK: - Apple Intelligence clock schemas
//
// Without these, Siri treats "Set a Wakie alarm for 6:13 PM" as a request for the
// built-in Clock app and uses "Wakie" as the alarm's label. Adopting the clock
// schemas tells Siri that Wakie is an alarm app, so those requests come here.
// Siri only fills the schema's own fields (time, label, repeat days, snooze), so
// the challenge is asked for inside `perform()`. These intents are hidden from the
// Shortcuts app, where the intents above keep serving existing shortcuts.

@AppEnum(schema: .clock.alarmTriggerState)
nonisolated enum WakieAlarmTriggerState: String {
    case firing
    case snoozed
    case none

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .firing: "Ringing",
        .snoozed: "Snoozed",
        .none: "Not Ringing",
    ]
}

@AppEntity(schema: .clock.alarm)
struct WakieAlarmEntity {
    static let defaultQuery = WakieAlarmEntityQuery()

    let id: UUID

    var time: DateComponents
    var isEnabled: Bool
    /// The challenge name, so Siri says "your 6:13 PM Shaky-Shaky alarm".
    var label: String?
    var recurrenceDays: Calendar.RecurrenceRule?
    var canSnooze: Bool
    var triggerState: WakieAlarmTriggerState

    var displayRepresentation: DisplayRepresentation {
        let alarm = DateComponents(hour: time.hour, minute: time.minute)
        let text = Calendar.current.date(from: alarm)?.formatted(date: .omitted, time: .shortened) ?? ""
        return DisplayRepresentation(title: "\(text)", subtitle: "\(label ?? "")")
    }

    init(_ alarm: WakieAlarm, session: WakeSession?) {
        id = alarm.id
        var components = DateComponents(hour: alarm.hour, minute: alarm.minute)
        if alarm.timeZoneID != nil { components.timeZone = alarm.timeZone }
        time = components
        isEnabled = alarm.isEnabled
        label = alarm.mission.title
        recurrenceDays = recurrenceRule(for: alarm.repeatDays)
        canSnooze = alarm.snoozeMinutes > 0
        if session?.alarmID == alarm.id {
            triggerState = .firing
        } else {
            triggerState = .none
        }
    }
}

nonisolated struct WakieAlarmEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [WakieAlarmEntity] {
        await MainActor.run {
            let model = AppModel.shared
            return model.alarms.filter { identifiers.contains($0.id) }.map { WakieAlarmEntity($0, session: model.session) }
        }
    }

    func suggestedEntities() async throws -> [WakieAlarmEntity] {
        await MainActor.run {
            let model = AppModel.shared
            return model.sortedAlarms.map { WakieAlarmEntity($0, session: model.session) }
        }
    }

    /// Finds alarms by what people say: "7 AM", "7:30", or a challenge like "Shaky-Shaky".
    func entities(matching string: String) async throws -> [WakieAlarmEntity] {
        let query = string.lowercased().replacingOccurrences(of: ".", with: "")
        return await MainActor.run {
            let model = AppModel.shared
            return model.sortedAlarms.filter { alarm in
                let time = "\(alarm.timeText) \(alarm.periodText)".lowercased()
                let hourOnly = "\(alarm.hour12) \(alarm.periodText)".lowercased()
                return time.contains(query) || query.contains(time) || (alarm.minute == 0 && query.contains(hourOnly))
                    || mission(fromLabel: query) == alarm.mission
            }.map { WakieAlarmEntity($0, session: model.session) }
        }
    }
}

// MARK: Schema helpers

/// Repeat days as the weekly rule the clock schema uses. `nil` means a one-time alarm.
private nonisolated func recurrenceRule(for days: Set<Weekday>) -> Calendar.RecurrenceRule? {
    guard !days.isEmpty else { return nil }
    return .weekly(calendar: .current, weekdays: days.sorted().map { .every($0.localeWeekday) })
}

/// Repeat days from the rule Siri understood ("every Tuesday and Friday", "every day").
private nonisolated func weekdays(from rule: Calendar.RecurrenceRule?) -> Set<Weekday> {
    guard let rule else { return [] }
    if rule.frequency == .daily { return Set(Weekday.allCases) }
    return Set(rule.weekdays.compactMap { day -> Weekday? in
        let localeDay: Locale.Weekday
        switch day {
        case .every(let weekday): localeDay = weekday
        case .nth(_, let weekday): localeDay = weekday
        @unknown default: return nil
        }
        return Weekday.allCases.first { $0.localeWeekday == localeDay }
    })
}

/// A challenge named in the alarm's label, like "Shaky-Shaky" or "dance".
private nonisolated func mission(fromLabel label: String?) -> Mission? {
    guard let text = label?.lowercased() else { return nil }
    if ["shak", "dance"].contains(where: text.contains) { return .shakyShaky }
    if ["pick", "find"].contains(where: text.contains) { return .pickiePicky }
    if ["blah", "talk", "speak"].contains(where: text.contains) { return .blahBlah }
    return nil
}

/// Applies a time Siri understood, including a time zone when the person named one ("8 PM New York time").
private nonisolated func apply(_ time: DateComponents, to alarm: inout WakieAlarm) {
    alarm.hour = time.hour ?? alarm.hour
    alarm.minute = time.minute ?? 0
    guard let zone = time.timeZone else { return }
    if zone.identifier == TimeZone.current.identifier {
        alarm.timeZoneID = nil
        alarm.placeName = nil
        alarm.placeFlag = nil
    } else {
        alarm.timeZoneID = zone.identifier
        alarm.placeName = WorldCity.cityName(fromTimeZoneID: zone.identifier)
        alarm.placeFlag = "🌍"
    }
}

/// Ready-to-speak description, like "6:13 PM New York time Shaky-Shaky alarm, every Tue & Fri".
private nonisolated func spokenSummary(of alarm: WakieAlarm) -> String {
    let place = alarm.timeZoneID == nil ? "" : " \(alarm.placeName ?? "") time"
    let repeats = alarm.isRepeating ? ", \(alarm.repeatText.lowercased())" : ""
    return "\(alarm.timeText) \(alarm.periodText)\(place) \(alarm.mission.title) alarm\(repeats)"
}

// MARK: Create

@AppIntent(schema: .clock.createAlarm)
struct SiriCreateAlarmIntent {
    static let isAssistantOnly: Bool = true

    var time: DateComponents
    var label: String?
    var recurrenceDays: Calendar.RecurrenceRule?
    var canSnooze: Bool

    func perform() async throws -> some ReturnsValue<WakieAlarmEntity> & ProvidesDialog {
        var alarm = WakieAlarm()
        apply(time, to: &alarm)
        alarm.repeatDays = weekdays(from: recurrenceDays)
        if canSnooze { alarm.snoozeMinutes = 5 }

        // Use a challenge named in the request, otherwise ask with just the three names.
        if let named = mission(fromLabel: label) {
            alarm.mission = named
        } else {
            let shaky = IntentChoiceOption(title: "Shaky-Shaky")
            let picky = IntentChoiceOption(title: "Pickie-Picky")
            let blah = IntentChoiceOption(title: "Blah-Blah")
            let choice = try await requestChoice(between: [shaky, picky, blah],
                                                 dialog: "Which challenge: Shaky-Shaky, Pickie-Picky, or Blah-Blah?")
            alarm.mission = choice == shaky ? .shakyShaky : choice == picky ? .pickiePicky : .blahBlah
        }

        // Saving is the irreversible step, so it happens after every question is answered.
        let saved = alarm
        let scheduled = await AppModel.shared.saveAndSchedule(saved)
        let entity = await MainActor.run { WakieAlarmEntity(saved, session: AppModel.shared.session) }
        guard scheduled else {
            return .result(value: entity, dialog: "I saved the alarm, but Wakie isn't allowed to ring alarms yet. Open Wakie to allow it.")
        }
        return .result(value: entity, dialog: "Done! Your \(spokenSummary(of: saved)) is set.")
    }
}

// MARK: Update

@AppIntent(schema: .clock.updateAlarm)
struct SiriUpdateAlarmIntent {
    static let isAssistantOnly: Bool = true

    var alarm: WakieAlarmEntity
    var isEnabled: Bool?
    var time: DateComponents?
    var label: String?
    var recurrenceDays: Calendar.RecurrenceRule?
    var allowsSnooze: Bool?

    func perform() async throws -> some ReturnsValue<WakieAlarmEntity> & ProvidesDialog {
        let id = alarm.id
        guard var stored = await MainActor.run(body: { AppModel.shared.alarms.first { $0.id == id } }) else {
            return .result(value: alarm, dialog: "I couldn't find that alarm.")
        }
        if let time { apply(time, to: &stored) }
        if let recurrenceDays { stored.repeatDays = weekdays(from: recurrenceDays) }
        if let named = mission(fromLabel: label) { stored.mission = named }
        if let allowsSnooze { stored.snoozeMinutes = allowsSnooze ? max(stored.snoozeMinutes, 5) : 0 }
        if let isEnabled { stored.isEnabled = isEnabled }

        let updated = stored
        await AppModel.shared.saveAndSchedule(updated)
        let entity = await MainActor.run { WakieAlarmEntity(updated, session: AppModel.shared.session) }
        let state = updated.isEnabled ? "" : " It's turned off."
        return .result(value: entity, dialog: "Updated. It's now a \(spokenSummary(of: updated)).\(state)")
    }
}

// MARK: Dismiss

/// A Wakie alarm only stops once its challenge is done, so instead of silencing it
/// this opens Wakie to the challenge.
@AppIntent(schema: .clock.dismissAlarm)
struct SiriDismissAlarmIntent {
    static let isAssistantOnly: Bool = true
    static let supportedModes: IntentModes = .foreground(.immediate)

    var alarm: WakieAlarmEntity

    func perform() async throws -> some ReturnsValue<WakieAlarmEntity> & ProvidesDialog {
        .result(value: alarm, dialog: "Wakie alarms stop when you finish your \(alarm.label ?? "") challenge. Let's do it!")
    }
}

// MARK: Snooze

@AppIntent(schema: .clock.snoozeAlarm)
struct SiriSnoozeAlarmIntent {
    static let isAssistantOnly: Bool = true

    var alarm: WakieAlarmEntity
    var duration: Duration

    func perform() async throws -> some ReturnsValue<WakieAlarmEntity> & ProvidesDialog {
        let id = alarm.id
        // Snoozing uses the alarm's own snooze length and is allowed once per ring.
        let snoozed = await MainActor.run { () -> Bool in
            let model = AppModel.shared
            guard let session = model.session, session.alarmID == id, session.canSnooze else { return false }
            model.snoozeCurrentSession()
            return true
        }
        guard snoozed else {
            return .result(value: alarm, dialog: "This alarm can't be snoozed. Finish your challenge to turn it off.")
        }
        return .result(value: alarm, dialog: "Snoozed. I'll ring again soon.")
    }
}

// MARK: Delete

@AppIntent(schema: .clock.deleteAlarm)
struct SiriDeleteAlarmIntent: DeleteIntent {
    static let isAssistantOnly: Bool = true

    var entities: [WakieAlarmEntity]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !entities.isEmpty else { return .result(dialog: "There's no alarm to delete.") }
        // Deleting can't be undone, so confirm first.
        try await requestConfirmation(
            actionName: .custom(acceptLabel: "Delete", acceptAlternatives: ["Yes", "Remove"], denyLabel: "Keep", denyAlternatives: ["No"], destructive: true),
            dialog: entities.count == 1 ? IntentDialog("Delete this alarm?") : IntentDialog("Delete these \(entities.count) alarms?")
        )
        let ids = entities.map(\.id)
        await MainActor.run { ids.forEach(AppModel.shared.delete) }
        return .result(dialog: entities.count == 1 ? "Deleted the alarm." : "Deleted \(entities.count) alarms.")
    }
}
