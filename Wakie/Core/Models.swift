//
//  Models.swift
//  Wakie
//

import Foundation
import SwiftUI

// MARK: - Mission

/// The three wake-up challenges a person must finish to silence an alarm.
nonisolated enum Mission: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case shakyShaky
    case pickiePicky
    case blahBlah

    var id: String { rawValue }

    /// Name used in lists and subtitles ("Shaky-Shaky").
    var title: String {
        switch self {
        case .shakyShaky: "Shaky-Shaky"
        case .pickiePicky: "Pickie-Picky"
        case .blahBlah: "Blah-Blah"
        }
    }

    /// Two-line label used on the challenge tiles.
    var tileTitle: String {
        switch self {
        case .shakyShaky: "Shaky\nShaky"
        case .pickiePicky: "Pickie\nPicky"
        case .blahBlah: "Blah\nBlah"
        }
    }

    /// Asset catalog name of the mascot artwork.
    var mascot: String {
        switch self {
        case .shakyShaky: "ShakyShaky"
        case .pickiePicky: "PickyPicky"
        case .blahBlah: "BlahBlah"
        }
    }

    var symbol: String {
        switch self {
        case .shakyShaky: "figure.dance"
        case .pickiePicky: "shuffle"
        case .blahBlah: "mic.fill"
        }
    }

    var tagline: String {
        switch self {
        case .shakyShaky: "Dance it out to stop the alarm"
        case .pickiePicky: "Find the item and show it"
        case .blahBlah: "Talk your way awake"
        }
    }

    var bannerColor: Color {
        switch self {
        case .shakyShaky: Theme.yellow
        case .pickiePicky: Theme.lavender
        case .blahBlah: Theme.peach
        }
    }
}

// MARK: - Weekday

/// Weekdays in the design's Monday-first order.
nonisolated enum Weekday: Int, Codable, CaseIterable, Identifiable, Hashable, Sendable, Comparable {
    case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var initial: String {
        ["M", "T", "W", "T", "F", "S", "S"][rawValue]
    }

    var shortName: String {
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][rawValue]
    }

    var fullName: String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][rawValue]
    }

    /// Matches `Calendar.component(.weekday, ...)` where Sunday == 1.
    var calendarWeekday: Int {
        self == .sunday ? 1 : rawValue + 2
    }

    var localeWeekday: Locale.Weekday {
        switch self {
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        case .sunday: .sunday
        }
    }

    init?(calendarWeekday: Int) {
        self.init(rawValue: calendarWeekday == 1 ? 6 : calendarWeekday - 2)
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Alarm

nonisolated struct WakieAlarm: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var hour: Int = 7          // 0...23
    var minute: Int = 0
    var repeatDays: Set<Weekday> = []
    var mission: Mission = .shakyShaky
    /// File name of a custom sound in Library/Sounds. `nil` plays the system alarm sound.
    var soundFile: String?
    /// 0 disables snoozing; otherwise 1...5 minutes, usable once per ring.
    var snoozeMinutes: Int = 0
    var isEnabled = true
    /// For one-off alarms: the moment it was scheduled to ring, so stale alarms can be switched off.
    var oneShotFireDate: Date?
    /// Time zone the alarm's hour and minute are in. `nil` means the device's own time zone.
    var timeZoneID: String?
    /// Display name and flag for `timeZoneID`, saved when the place was picked.
    var placeName: String?
    var placeFlag: String?

    var isRepeating: Bool { !repeatDays.isEmpty }

    var hour12: Int {
        let h = hour % 12
        return h == 0 ? 12 : h
    }

    var isPM: Bool { hour >= 12 }

    var timeText: String { "\(hour12):" + String(format: "%02d", minute) }

    var periodText: String { isPM ? "PM" : "AM" }

    var repeatText: String {
        let days = repeatDays.sorted()
        switch days.count {
        case 0: return "Alarm"
        case 7: return "Every day"
        case 1: return "Every \(days[0].fullName)"
        case 2: return "\(days[0].shortName) & \(days[1].shortName)"
        default:
            if Set(days) == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "Weekdays" }
            if Set(days) == [.saturday, .sunday] { return "Weekends" }
            return days.map(\.shortName).joined(separator: ", ")
        }
    }

    var subtitle: String { "\(repeatText) · \(mission.title)" }

    var soundTitle: String {
        guard let soundFile else { return "Wakie Rise" }
        return ToneLibrary.title(forFile: soundFile) ?? AudioImporter.title(forFile: soundFile)
    }

    var timeZone: TimeZone {
        timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// Whether the alarm uses the same clock as the phone right now.
    var isLocal: Bool {
        timeZoneID == nil || timeZone.secondsFromGMT() == TimeZone.current.secondsFromGMT()
    }

    /// Label for the alarm's place, e.g. "🇮🇹 Naples".
    var placeLabel: String {
        if timeZoneID == nil { return LocalPlace.label }
        return "\(placeFlag ?? "🌍") \(placeName ?? WorldCity.cityName(fromTimeZoneID: timeZone.identifier))"
    }

    /// The alarm's ring time on the phone's own clock, e.g. "11:34 AM".
    func localTimeText(now: Date = .now) -> String {
        guard let fire = nextFireDate(after: now) else { return "" }
        return fire.formatted(date: .omitted, time: .shortened)
    }

    /// Hour, minute and weekdays on the phone's clock, which is what AlarmKit schedules against.
    func localSchedule(now: Date = .now) -> (hour: Int, minute: Int, days: Set<Weekday>) {
        guard !isLocal, let fire = nextFireDate(after: now) else { return (hour, minute, repeatDays) }
        let local = Calendar.current
        let parts = local.dateComponents([.hour, .minute], from: fire)
        // Each repeat day may land on a different local weekday (e.g. Monday 2 AM in Rome is Sunday in New York).
        let days = Set(repeatDays.compactMap { day -> Weekday? in
            guard let date = nextFireDate(after: now, only: day) else { return nil }
            return Weekday(calendarWeekday: local.component(.weekday, from: date))
        })
        return (parts.hour ?? hour, parts.minute ?? minute, days)
    }

    /// The next moment this alarm will ring after `date`, in the alarm's own time zone.
    func nextFireDate(after date: Date = .now, only day: Weekday? = nil) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        if let day {
            components.weekday = day.calendarWeekday
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }
        if repeatDays.isEmpty {
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }
        return repeatDays.compactMap { day -> Date? in
            var c = components
            c.weekday = day.calendarWeekday
            return calendar.nextDate(after: date, matching: c, matchingPolicy: .nextTime)
        }.min()
    }
}


// MARK: - Pickie-Picky items

nonisolated struct PickItem: Codable, Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let emoji: String
    /// Labels from Vision's built-in image classifier that count as this item.
    let labels: [String]

    static let defaults: [PickItem] = [
        PickItem(name: "Spoon", emoji: "🥄", labels: ["spoon", "utensil"]),
        PickItem(name: "Fork", emoji: "🍴", labels: ["fork", "utensil"]),
        PickItem(name: "Watch", emoji: "⌚️", labels: ["watch", "stopwatch", "clock"]),
        PickItem(name: "Pen", emoji: "🖊️", labels: ["pen"]),
        PickItem(name: "Mug", emoji: "☕️", labels: ["mug", "cup"]),
        PickItem(name: "Bottle", emoji: "🧴", labels: ["bottle", "wine_bottle"]),
        PickItem(name: "Book", emoji: "📚", labels: ["book"]),
        PickItem(name: "Shoe", emoji: "👟", labels: ["shoes", "sneaker", "footwear"]),
        PickItem(name: "Glasses", emoji: "👓", labels: ["eyeglasses", "sunglasses"]),
        PickItem(name: "Scissors", emoji: "✂️", labels: ["scissors"]),
    ]
}

// MARK: - Stats

nonisolated struct WakeStats: Codable, Sendable {
    var wakeUps = 0
    var totalSecondsToWake: Double = 0

    var averageSecondsToWake: Double {
        wakeUps == 0 ? 0 : totalSecondsToWake / Double(wakeUps)
    }

    var averageText: String {
        let s = Int(averageSecondsToWake.rounded())
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

// MARK: - Ringing session

/// State for an alarm that has fired and is waiting for its mission to be completed.
nonisolated struct WakeSession: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { alarmID }
    let alarmID: UUID
    let mission: Mission
    let startedAt: Date
    /// Whether the one allowed snooze is still available.
    var canSnooze: Bool
    var snoozeMinutes: Int
    /// A follow-up alarm that rings again if the mission isn't finished.
    var backupAlarmID: UUID?
}

/// What the full-screen mission view is showing.
struct MissionRun: Identifiable, Hashable {
    let id = UUID()
    let mission: Mission
    let isPractice: Bool
}

// MARK: - World clock

nonisolated struct WorldCity: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var country: String
    var flag: String
    var timeZoneID: String
    /// Built-in banner artwork in the asset catalog.
    var banner: String?
    /// File name of a photo the person picked, stored in `WorldCity.photosDirectory`.
    var photoFile: String?

    init(id: String = UUID().uuidString, name: String, country: String, flag: String,
         timeZoneID: String, banner: String? = nil, photoFile: String? = nil) {
        self.id = id
        self.name = name
        self.country = country
        self.flag = flag
        self.timeZoneID = timeZoneID
        self.banner = banner
        self.photoFile = photoFile
    }

    // Older saves have no id or country, so decode those leniently.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timeZoneID = try c.decode(String.self, forKey: .timeZoneID)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? timeZoneID
        name = try c.decode(String.self, forKey: .name)
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        flag = try c.decode(String.self, forKey: .flag)
        banner = try c.decodeIfPresent(String.self, forKey: .banner)
        photoFile = try c.decodeIfPresent(String.self, forKey: .photoFile)
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    var photoURL: URL? {
        photoFile.map { Self.photosDirectory.appending(path: $0) }
    }

    static var photosDirectory: URL {
        let url = URL.documentsDirectory.appending(path: "CityPhotos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// "Asia/Kolkata" -> "Kolkata"
    static func cityName(fromTimeZoneID id: String) -> String {
        (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
    }

    /// Finds the ISO region code for a country name such as "India" (in English or the
    /// phone's language). Used when Maps doesn't return a code, e.g. for Jammu.
    static func regionCode(forCountryName name: String) -> String? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }
        let locales = [Locale.current, Locale(identifier: "en_US")]
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            // Skip continents and other numeric groupings.
            guard code.count == 2, code.allSatisfy(\.isLetter) else { continue }
            if code.lowercased() == target { return code }
            for locale in locales where locale.localizedString(forRegionCode: code)?.lowercased() == target {
                return code
            }
        }
        return nil
    }

    /// Flag for a country name, or the globe if it can't be matched.
    static func flag(forCountryName name: String) -> String {
        regionCode(forCountryName: name).map(flag(forRegionCode:)) ?? "🌍"
    }

    /// Best flag for a place: from its country name, else borrowed from another known
    /// city in the same time zone (e.g. Jammu shares Asia/Kolkata with Kolkata and Chennai).
    static func bestFlag(country: String, timeZoneID: String, knownCities: [WorldCity]) -> String {
        let byName = flag(forCountryName: country)
        if byName != "🌍" { return byName }
        return knownCities.first { $0.timeZoneID == timeZoneID && $0.flag != "🌍" }?.flag ?? "🌍"
    }

    /// Turns an ISO region code like "IT" into its flag emoji.
    static func flag(forRegionCode code: String) -> String {
        let base: UInt32 = 0x1F1E6 - 65 // regional indicator "A" minus ASCII "A"
        let scalars = code.uppercased().unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : "🌍"
    }

    /// Starting cities. Jammu and Colombo get their photos fetched online on first launch.
    static let defaults: [WorldCity] = [
        WorldCity(id: "Europe/Rome", name: "Naples", country: "Italy", flag: "🇮🇹", timeZoneID: "Europe/Rome", banner: "BannerNaples"),
        WorldCity(id: "Asia/Kolkata", name: "Jammu", country: "India", flag: "🇮🇳", timeZoneID: "Asia/Kolkata"),
        WorldCity(id: "Asia/Colombo", name: "Colombo", country: "Sri Lanka", flag: "🇱🇰", timeZoneID: "Asia/Colombo"),
    ]

    /// The starting list from earlier versions, replaced by `defaults` if left untouched.
    static let previousDefaultNames = ["Naples", "Chennai", "Riga"]
}

/// The phone's own location. Uses the World Clock city in the phone's time zone when
/// there is one (e.g. Naples for Europe/Rome), so the name and flag match where you are.
/// The phone's region setting isn't used: it describes language/format, not location.
nonisolated enum LocalPlace {
    /// The saved World Clock city sharing the phone's time zone, if any.
    static var matchingCity: WorldCity? {
        let saved = UserDefaults.standard.data(forKey: "cities")
            .flatMap { try? JSONDecoder().decode([WorldCity].self, from: $0) } ?? WorldCity.defaults
        return saved.first { $0.timeZoneID == TimeZone.current.identifier }
    }

    static var name: String {
        matchingCity?.name ?? WorldCity.cityName(fromTimeZoneID: TimeZone.current.identifier)
    }

    static var flag: String { matchingCity?.flag ?? "📍" }
    static var label: String { "\(flag) \(name)" }
}

// MARK: - Recordings

struct VoiceRecording: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let date: Date
    let duration: TimeInterval

    var durationText: String {
        let s = Int(duration.rounded())
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
