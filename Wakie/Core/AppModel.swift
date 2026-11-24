//
//  AppModel.swift
//  Wakie
//
//  Owns alarms, settings, stats and the "alarm is ringing" flow. Persisted in UserDefaults.
//

import Foundation
import Observation
import AVFoundation

@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Persisted state

    var alarms: [WakieAlarm] { didSet { store(alarms, for: Keys.alarms) } }
    var stats: WakeStats { didSet { store(stats, for: Keys.stats) } }
    var cities: [WorldCity] { didSet { store(cities, for: Keys.cities) } }
    var pickItems: [PickItem] { didSet { store(pickItems, for: Keys.pickItems) } }
    var danceSeconds: Int { didSet { defaults.set(danceSeconds, forKey: Keys.danceSeconds) } }
    var talkSeconds: Int { didSet { defaults.set(talkSeconds, forKey: Keys.talkSeconds) } }
    var isNight: Bool { didSet { defaults.set(isNight, forKey: Keys.isNight) } }
    /// Song played while dancing in Shaky-Shaky, stored in `AudioImporter.danceMusicDirectory`.
    var danceSongFile: String? { didSet { defaults.set(danceSongFile, forKey: Keys.danceSongFile) } }

    /// The alarm currently waiting for its mission. Drives the full-screen ringing view.
    var session: WakeSession? { didSet { store(session, for: Keys.session) } }

    /// Maps follow-up (snooze / backup) system alarm IDs to the alarm they belong to.
    private var followUps: [UUID: UUID] { didSet { store(followUps, for: Keys.followUps) } }

    // MARK: Transient state

    var recordings: [VoiceRecording] = []
    /// Custom alarm sounds (file names in Library/Sounds).
    var alarmSounds: [String] = []
    var alarmsDenied = false
    private var observationTask: Task<Void, Never>?

    private let defaults = UserDefaults.standard

    /// Allowed length for the timed missions (Shaky-Shaky dancing and Blah-Blah talking).
    static let missionSecondsRange = 5...30

    private enum Keys {
        static let alarms = "alarms"
        static let stats = "stats"
        static let cities = "cities"
        static let pickItems = "pickItems"
        static let danceSeconds = "danceSeconds"
        static let talkSeconds = "talkSeconds"
        static let isNight = "isNight"
        static let session = "session"
        static let followUps = "followUps"
        static let danceSongFile = "danceSongFile"
    }

    private init() {
        let d = UserDefaults.standard
        // Alarms keep their own copy of the place's flag; repair missing ones using the city's country.
        let savedCities = Self.load([WorldCity].self, from: d, key: Keys.cities) ?? WorldCity.defaults
        alarms = (Self.load([WakieAlarm].self, from: d, key: Keys.alarms) ?? []).map { alarm in
            guard alarm.placeFlag == "🌍", let name = alarm.placeName,
                  let city = savedCities.first(where: { $0.name == name && $0.timeZoneID == alarm.timeZoneID }) else { return alarm }
            var fixed = alarm
            fixed.placeFlag = WorldCity.bestFlag(country: city.country, timeZoneID: city.timeZoneID,
                                                 knownCities: savedCities + WorldCity.defaults)
            return fixed
        }
        stats = Self.load(WakeStats.self, from: d, key: Keys.stats) ?? WakeStats()
        // Repair cities saved without a flag (Maps gave no region code) using their country name.
        cities = savedCities.map { city in
            guard city.flag == "🌍" else { return city }
            var fixed = city
            fixed.flag = WorldCity.bestFlag(country: city.country, timeZoneID: city.timeZoneID,
                                            knownCities: savedCities + WorldCity.defaults)
            return fixed
        }
        pickItems = Self.load([PickItem].self, from: d, key: Keys.pickItems) ?? PickItem.defaults
        danceSeconds = min(max(d.object(forKey: Keys.danceSeconds) as? Int ?? 20, Self.missionSecondsRange.lowerBound), Self.missionSecondsRange.upperBound)
        talkSeconds = min(max(d.object(forKey: Keys.talkSeconds) as? Int ?? 30, Self.missionSecondsRange.lowerBound), Self.missionSecondsRange.upperBound)
        isNight = d.bool(forKey: Keys.isNight)
        danceSongFile = d.string(forKey: Keys.danceSongFile)
        session = Self.load(WakeSession.self, from: d, key: Keys.session)
        followUps = Self.load([UUID: UUID].self, from: d, key: Keys.followUps) ?? [:]
        refreshRecordings()
        refreshAlarmSounds()
    }

    // MARK: Persistence helpers

    private func store<T: Encodable>(_ value: T?, for key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Lifecycle

    /// Called once at launch: tidies stale alarms, syncs with the system and listens for ringing alarms.
    func start() {
        guard observationTask == nil else { return }
        disableExpiredOneShots()
        Task { await syncWithSystem() }
        observationTask = Task { [weak self] in
            for await ringing in AlarmScheduler.alertingUpdates() {
                self?.handleAlerting(ringing)
            }
        }
    }

    /// One-off alarms that already rang are switched off, like the stock Clock app.
    private func disableExpiredOneShots() {
        let now = Date.now
        for index in alarms.indices where !alarms[index].isRepeating && alarms[index].isEnabled {
            if let fire = alarms[index].oneShotFireDate, fire < now.addingTimeInterval(-60) {
                alarms[index].isEnabled = false
            }
        }
    }

    /// Makes sure every enabled alarm is registered with AlarmKit and nothing else is.
    private func syncWithSystem() async {
        let scheduled = AlarmScheduler.scheduledIDs()
        let enabledIDs = Set(alarms.filter(\.isEnabled).map(\.id))
        let followUpIDs = Set(followUps.keys)
        for id in scheduled where !enabledIDs.contains(id) && !followUpIDs.contains(id) {
            AlarmScheduler.cancel(id)
        }
        // Drop follow-up bookkeeping for alarms the system no longer knows about.
        followUps = followUps.filter { scheduled.contains($0.key) }
        let missing = alarms.filter { $0.isEnabled && !scheduled.contains($0.id) }
        guard !missing.isEmpty, await AlarmScheduler.requestAuthorization() else { return }
        for alarm in missing {
            try? await AlarmScheduler.schedule(alarm)
        }
    }

    // MARK: - Alarm CRUD

    var sortedAlarms: [WakieAlarm] {
        alarms.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    /// The enabled alarm that will ring soonest, with its fire date.
    var upcoming: (alarm: WakieAlarm, date: Date)? {
        alarms.filter(\.isEnabled)
            .compactMap { alarm in alarm.nextFireDate().map { (alarm, $0) } }
            .min { $0.1 < $1.1 }
    }

    func save(_ alarm: WakieAlarm) {
        let alarm = store(alarm)
        Task { await register(alarm) }
    }

    /// Saves and waits until the system has the alarm. Used by Siri so it can report back.
    /// Returns `false` if Wakie isn't allowed to schedule alarms.
    @discardableResult
    func saveAndSchedule(_ alarm: WakieAlarm) async -> Bool {
        let alarm = store(alarm)
        await register(alarm)
        return !alarmsDenied
    }

    private func store(_ alarm: WakieAlarm) -> WakieAlarm {
        var alarm = alarm
        alarm.isEnabled = true
        alarm.oneShotFireDate = alarm.isRepeating ? nil : alarm.nextFireDate()
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        return alarm
    }

    func delete(_ id: UUID) {
        alarms.removeAll { $0.id == id }
        AlarmScheduler.cancel(id)
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].isEnabled = enabled
        if enabled {
            if !alarms[index].isRepeating {
                alarms[index].oneShotFireDate = alarms[index].nextFireDate()
            }
            let alarm = alarms[index]
            Task { await register(alarm) }
        } else {
            AlarmScheduler.cancel(id)
        }
    }

    private func register(_ alarm: WakieAlarm) async {
        guard await AlarmScheduler.requestAuthorization() else {
            alarmsDenied = true
            return
        }
        alarmsDenied = false
        do {
            try await AlarmScheduler.schedule(alarm)
        } catch {
            print("Failed to schedule alarm: \(error)")
        }
    }

    // MARK: - Ringing flow

    private func sourceAlarm(forSystemID id: UUID) -> WakieAlarm? {
        let sourceID = followUps[id] ?? id
        return alarms.first { $0.id == sourceID }
    }

    /// The app saw a Wakie alarm start ringing while it was running.
    private func handleAlerting(_ ringingIDs: [UUID]) {
        guard session == nil else { return }
        for id in ringingIDs {
            guard let alarm = sourceAlarm(forSystemID: id) else { continue }
            let isFollowUp = followUps[id] != nil
            session = WakeSession(
                alarmID: alarm.id,
                mission: alarm.mission,
                startedAt: .now,
                canSnooze: !isFollowUp && alarm.snoozeMinutes > 0,
                snoozeMinutes: alarm.snoozeMinutes,
                backupAlarmID: nil
            )
            return
        }
    }

    /// The person tapped "Stop" on the system alarm UI. The alarm is already silent,
    /// so arm a backup alarm in case they go back to sleep instead of doing the mission.
    func handleSystemStop(alarmID: UUID, kitAlarmID: UUID) async {
        guard let alarm = alarms.first(where: { $0.id == alarmID }) else { return }
        let isFollowUp = kitAlarmID != alarmID
        followUps[kitAlarmID] = nil
        if session?.alarmID != alarmID {
            session = WakeSession(
                alarmID: alarm.id,
                mission: alarm.mission,
                startedAt: .now,
                canSnooze: !isFollowUp && alarm.snoozeMinutes > 0,
                snoozeMinutes: alarm.snoozeMinutes,
                backupAlarmID: nil
            )
        }
        await armBackup(after: 120)
    }

    /// Snoozes the ringing alarm (from the system button or the in-app control). Only once.
    func snooze(alarmID: UUID, kitAlarmID: UUID) async {
        guard let alarm = alarms.first(where: { $0.id == alarmID }), alarm.snoozeMinutes > 0 else { return }
        // Follow-up alarms never offer snooze, so a snooze request for one is ignored.
        guard followUps[kitAlarmID] == nil else { return }
        AlarmScheduler.stopIfAlerting(kitAlarmID)
        if let backup = session?.backupAlarmID {
            AlarmScheduler.cancel(backup)
            followUps[backup] = nil
        }
        session = nil
        let snoozeID = UUID()
        followUps[snoozeID] = alarm.id
        let fireDate = Date.now.addingTimeInterval(TimeInterval(alarm.snoozeMinutes * 60))
        do {
            try await AlarmScheduler.scheduleFollowUp(id: snoozeID, at: fireDate, sourceAlarmID: alarm.id,
                                                      mission: alarm.mission, soundFile: alarm.soundFile)
        } catch {
            followUps[snoozeID] = nil
            print("Failed to snooze: \(error)")
        }
    }

    /// In-app snooze from the ringing screen.
    func snoozeCurrentSession() {
        guard let session, session.canSnooze else { return }
        Task { await snooze(alarmID: session.alarmID, kitAlarmID: session.alarmID) }
    }

    /// The mission began: silence anything still ringing (so it doesn't drown out the
    /// microphone) and push the backup alarm out past the mission's expected length.
    func missionDidStart() {
        guard let session else { return }
        AlarmScheduler.stopIfAlerting(session.alarmID)
        for (kitID, source) in followUps where source == session.alarmID && kitID != session.backupAlarmID {
            AlarmScheduler.stopIfAlerting(kitID)
        }
        let expected: TimeInterval = switch session.mission {
        case .shakyShaky: TimeInterval(danceSeconds) + 60
        case .blahBlah: TimeInterval(talkSeconds) + 60
        case .pickiePicky: 180
        }
        Task { await armBackup(after: expected + 90) }
    }

    private func armBackup(after seconds: TimeInterval) async {
        guard var current = session else { return }
        if let old = current.backupAlarmID {
            AlarmScheduler.cancel(old)
            followUps[old] = nil
        }
        let backupID = UUID()
        followUps[backupID] = current.alarmID
        current.backupAlarmID = backupID
        session = current
        do {
            try await AlarmScheduler.scheduleFollowUp(
                id: backupID,
                at: .now.addingTimeInterval(seconds),
                sourceAlarmID: current.alarmID,
                mission: current.mission,
                soundFile: alarms.first { $0.id == current.alarmID }?.soundFile
            )
        } catch {
            followUps[backupID] = nil
            print("Failed to arm backup alarm: \(error)")
        }
    }

    /// The mission was completed: stop everything, record stats and close the session.
    func completeSession() {
        guard let session else { return }
        endSession(session)
        stats.wakeUps += 1
        stats.totalSecondsToWake += Date.now.timeIntervalSince(session.startedAt)
    }

    /// Turns the alarm off without doing the mission. Doesn't count as a wake-up.
    func dismissSession() {
        guard let session else { return }
        endSession(session)
    }

    /// Silences the ringing alarm, cancels its snooze/backup follow-ups and closes the session.
    private func endSession(_ session: WakeSession) {
        AlarmScheduler.stopIfAlerting(session.alarmID)
        for (kitID, source) in followUps where source == session.alarmID {
            AlarmScheduler.cancel(kitID)
            followUps[kitID] = nil
        }
        if let index = alarms.firstIndex(where: { $0.id == session.alarmID }), !alarms[index].isRepeating {
            alarms[index].isEnabled = false
        }
        self.session = nil
    }

    // MARK: - Pickie-Picky

    func randomPickItem(excluding: PickItem? = nil) -> PickItem {
        let pool = pickItems.isEmpty ? PickItem.defaults : pickItems
        let choices = pool.count > 1 ? pool.filter { $0 != excluding } : pool
        return choices.randomElement() ?? PickItem.defaults[0]
    }

    func removePickItem(_ item: PickItem) {
        guard pickItems.count > 1 else { return }
        pickItems.removeAll { $0 == item }
    }

    func restorePickItems() {
        pickItems = PickItem.defaults
    }

    /// Items that were removed; shown greyed out so each can be brought back on its own.
    var removedPickItems: [PickItem] {
        PickItem.defaults.filter { !pickItems.contains($0) }
    }

    /// Brings back one removed item, in its usual place in the list.
    func restorePickItem(_ item: PickItem) {
        guard !pickItems.contains(item) else { return }
        pickItems.append(item)
        let order = PickItem.defaults.map(\.name)
        pickItems.sort { (order.firstIndex(of: $0.name) ?? .max) < (order.firstIndex(of: $1.name) ?? .max) }
    }

    // MARK: - Recordings

    static var recordingsDirectory: URL {
        let url = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func refreshRecordings() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: Self.recordingsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        recordings = urls
            .filter { $0.pathExtension == "m4a" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
                return VoiceRecording(url: url, date: date, duration: duration)
            }
            .sorted { $0.date > $1.date }
    }

    func deleteRecording(_ recording: VoiceRecording) {
        try? FileManager.default.removeItem(at: recording.url)
        refreshRecordings()
        refreshAlarmSounds()
    }

    // MARK: - Alarm sounds

    func refreshAlarmSounds() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: AudioImporter.alarmSoundsDirectory, includingPropertiesForKeys: nil)) ?? []
        alarmSounds = urls.map(\.lastPathComponent).filter { $0.hasSuffix(".caf") }.sorted()
    }

    /// Converts a song from Files into an alarm sound. Returns its file name.
    func importAlarmSound(from url: URL) async throws -> String {
        let file = try await Task.detached(priority: .userInitiated) {
            try AudioImporter.makeAlarmSound(from: url)
        }.value
        refreshAlarmSounds()
        return file
    }

    /// Deletes a custom sound; alarms that used it fall back to the default sound.
    func deleteAlarmSound(_ file: String) {
        try? FileManager.default.removeItem(at: AudioImporter.alarmSoundsDirectory.appending(path: file))
        refreshAlarmSounds()
        for index in alarms.indices where alarms[index].soundFile == file {
            alarms[index].soundFile = nil
            if alarms[index].isEnabled {
                let alarm = alarms[index]
                Task { await register(alarm) }
            }
        }
    }

    // MARK: - Dance music

    var danceSongURL: URL? {
        danceSongFile.map { AudioImporter.danceMusicDirectory.appending(path: $0) }
    }

    func importDanceSong(from url: URL) async throws {
        let file = try await Task.detached(priority: .userInitiated) {
            try AudioImporter.copyDanceSong(from: url)
        }.value
        removeDanceSong()
        danceSongFile = file
    }

    func removeDanceSong() {
        if let old = danceSongURL { try? FileManager.default.removeItem(at: old) }
        danceSongFile = nil
    }

    // MARK: - World clock

    func addCity(_ city: WorldCity) {
        cities.append(city)
    }

    /// Moves the cities with `ids` so they sit before `target` (or at the end when `nil`).
    func moveCities(_ ids: [String], before target: String?) {
        let moving = cities.filter { ids.contains($0.id) }
        var rest = cities.filter { !ids.contains($0.id) }
        let index = target.flatMap { id in rest.firstIndex { $0.id == id } } ?? rest.endIndex
        rest.insert(contentsOf: moving, at: index)
        cities = rest
    }

    func removeCity(_ city: WorldCity) {
        cities.removeAll { $0.id == city.id }
        if let url = city.photoURL { try? FileManager.default.removeItem(at: url) }
    }
}
