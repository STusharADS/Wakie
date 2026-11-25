//
//  AlarmScheduler.swift
//  Wakie
//
//  Thin wrapper around AlarmKit plus the intents wired to the system alarm buttons.
//

import Foundation
import SwiftUI
import AlarmKit
import AppIntents
import ActivityKit

/// Metadata attached to every Wakie alarm shown by the system.
nonisolated struct WakieAlarmMetadata: AlarmMetadata {
    var mission: Mission
}

enum AlarmScheduler {
    private static var manager: AlarmManager { AlarmManager.shared }

    /// Asks for permission to schedule alarms. Returns `true` when allowed.
    static func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let state = try? await manager.requestAuthorization()
            return state == .authorized
        @unknown default:
            return false
        }
    }

    /// Extra rings after the main one: if the system alert is stopped without doing the
    /// challenge, the alarm sounds again 30 seconds later, and again, for two minutes.
    /// Starting the challenge cancels them.
    static let chainLength = 4
    static let chainInterval: TimeInterval = 30

    /// Stable IDs for an alarm's extra rings, derived from the alarm's own ID.
    static func chainIDs(for id: UUID) -> [UUID] {
        (1...chainLength).map { index in
            var bytes = id.uuid
            bytes.14 ^= 0x5C
            bytes.15 ^= UInt8(0xA0 + index)
            return UUID(uuid: bytes)
        }
    }

    /// Schedules (or re-schedules) a repeating or one-off alarm at its wall-clock time,
    /// plus the extra rings that follow its next occurrence.
    static func schedule(_ alarm: WakieAlarm) async throws {
        cancel(alarm.id)
        // AlarmKit schedules against the phone's clock, so convert alarms set in another time zone.
        let local = alarm.localSchedule()
        let time = Alarm.Schedule.Relative.Time(hour: local.hour, minute: local.minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence = alarm.isRepeating
            ? .weekly(local.days.sorted().map(\.localeWeekday))
            : .never
        let relative = Alarm.Schedule.relative(.init(time: time, repeats: recurrence))
        try await register(
            id: alarm.id,
            schedule: relative,
            sourceAlarmID: alarm.id,
            mission: alarm.mission,
            snoozeMinutes: alarm.snoozeMinutes,
            soundFile: alarm.soundFile
        )
        guard let fire = alarm.nextFireDate() else { return }
        for (index, chainID) in chainIDs(for: alarm.id).enumerated() {
            try await register(
                id: chainID,
                schedule: .fixed(fire.addingTimeInterval(chainInterval * Double(index + 1))),
                sourceAlarmID: alarm.id,
                mission: alarm.mission,
                snoozeMinutes: 0,
                soundFile: alarm.soundFile
            )
        }
    }

    /// Schedules a one-time follow-up alarm (used for the single snooze and the mission backup).
    /// Follow-ups never offer a snooze button.
    static func scheduleFollowUp(id: UUID, at date: Date, sourceAlarmID: UUID, mission: Mission, soundFile: String?) async throws {
        cancel(id)
        try await register(
            id: id,
            schedule: .fixed(date),
            sourceAlarmID: sourceAlarmID,
            mission: mission,
            snoozeMinutes: 0,
            soundFile: soundFile
        )
    }

    private static func register(
        id: UUID,
        schedule: Alarm.Schedule,
        sourceAlarmID: UUID,
        mission: Mission,
        snoozeMinutes: Int,
        soundFile: String?
    ) async throws {
        // The default tone is generated on first launch; make sure it's there before AlarmKit needs it.
        await Task.detached(priority: .userInitiated) { ToneLibrary.ensureGenerated() }.value
        let allowsSnooze = snoozeMinutes > 0
        let alert = AlarmPresentation.Alert(
            title: "Time to wake up! \(mission.title)",
            secondaryButton: allowsSnooze
                ? AlarmButton(text: "Snooze \(snoozeMinutes)m", textColor: .white, systemImageName: "zzz")
                : nil,
            secondaryButtonBehavior: allowsSnooze ? .custom : nil
        )
        let attributes = AlarmAttributes<WakieAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakieAlarmMetadata(mission: mission),
            tintColor: Theme.purple
        )
        let configuration = AlarmManager.AlarmConfiguration<WakieAlarmMetadata>.alarm(
            schedule: schedule,
            attributes: attributes,
            // Ties the system alarm (and its snooze/backup follow-ups) to the Wakie alarm Siri
            // knows about, so requests like "stop the alarm" or "change my alarm" reach Wakie.
            appEntityIdentifier: EntityIdentifier(for: WakieAlarmEntity.self, identifier: sourceAlarmID),
            stopIntent: StartMissionIntent(alarmID: sourceAlarmID.uuidString, kitAlarmID: id.uuidString),
            secondaryIntent: allowsSnooze
                ? SnoozeOnceIntent(alarmID: sourceAlarmID.uuidString, kitAlarmID: id.uuidString)
                : nil,
            // Custom sounds live in Library/Sounds, where AlarmKit looks them up by name.
            // With no pick, Wakie's own loud tone plays instead of the quieter system sound.
            sound: .named(soundFile ?? ToneLibrary.defaultAlarmFile)
        )
        _ = try await manager.schedule(id: id, configuration: configuration)
    }

    /// Cancels an alarm and its extra rings.
    static func cancel(_ id: UUID) {
        try? manager.cancel(id: id)
        cancelChain(id)
    }

    /// Cancels only the extra rings, e.g. once the challenge has started.
    static func cancelChain(_ id: UUID) {
        for chainID in chainIDs(for: id) {
            stopIfAlerting(chainID)
            try? manager.cancel(id: chainID)
        }
    }

    /// Silences an alarm only if it's ringing right now, so future repeats stay intact.
    static func stopIfAlerting(_ id: UUID) {
        guard let alarms = try? manager.alarms,
              alarms.contains(where: { $0.id == id && $0.state == .alerting }) else { return }
        try? manager.stop(id: id)
    }

    /// IDs of alarms currently registered with the system.
    static func scheduledIDs() -> Set<UUID> {
        Set((try? manager.alarms)?.map(\.id) ?? [])
    }

    /// Emits the IDs of alarms that are ringing whenever the system alarm list changes.
    static func alertingUpdates() -> AsyncStream<[UUID]> {
        AsyncStream { continuation in
            let task = Task {
                for await alarms in manager.alarmUpdates {
                    continuation.yield(alarms.filter { $0.state == .alerting }.map(\.id))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Intents

/// Runs when the person taps the system "Stop" button. The alarm is silenced by the
/// system, so the app opens straight into the wake-up mission and arms a backup alarm.
struct StartMissionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Wake-Up Mission"
    static let description = IntentDescription("Opens Wakie to complete the alarm's mission.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    @Parameter(title: "System Alarm ID")
    var kitAlarmID: String

    init() {}

    init(alarmID: String, kitAlarmID: String) {
        self.alarmID = alarmID
        self.kitAlarmID = kitAlarmID
    }

    func perform() async throws -> some IntentResult {
        if let source = UUID(uuidString: alarmID), let kit = UUID(uuidString: kitAlarmID) {
            await AppModel.shared.handleSystemStop(alarmID: source, kitAlarmID: kit)
        }
        return .result()
    }
}

/// Runs when the person taps the system "Snooze" button. Snoozing is allowed once:
/// the follow-up alarm has no snooze button.
struct SnoozeOnceIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze Once"
    static let description = IntentDescription("Snoozes the alarm a single time.")
    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    @Parameter(title: "System Alarm ID")
    var kitAlarmID: String

    init() {}

    init(alarmID: String, kitAlarmID: String) {
        self.alarmID = alarmID
        self.kitAlarmID = kitAlarmID
    }

    func perform() async throws -> some IntentResult {
        if let source = UUID(uuidString: alarmID), let kit = UUID(uuidString: kitAlarmID) {
            await AppModel.shared.snooze(alarmID: source, kitAlarmID: kit)
        }
        return .result()
    }
}
