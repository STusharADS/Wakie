//
//  WidgetBridge.swift
//  Wakie
//
//  Shares upcoming alarm times with the Wakie widget through the app group, and asks
//  WidgetKit to refresh whenever alarms change. The widget keeps its own copy of
//  `WidgetAlarmOccurrence` with the same coding keys.
//

import Foundation
import WidgetKit

/// One upcoming ring of an alarm, ready for the widget to show.
nonisolated struct WidgetAlarmOccurrence: Codable, Sendable {
    let fireDate: Date
    /// The alarm's own clock time, e.g. "6:13" and "PM" (in its time zone).
    let timeText: String
    let periodText: String
    /// `Mission.rawValue`, so the widget can pick the mascot and title.
    let mission: String
    let repeatText: String
    /// "🇺🇸 New York" for alarms in another time zone, otherwise `nil`.
    let placeLabel: String?
}

nonisolated enum WidgetBridge {
    static let appGroupID = "group.ts.Wakie"
    static let occurrencesKey = "widgetUpcomingAlarms"
    static let widgetKind = "WakieWidget"

    /// Writes the next rings of every enabled alarm (about two weeks ahead) and reloads the widget.
    static func publish(_ alarms: [WakieAlarm], now: Date = .now) {
        let horizon = now.addingTimeInterval(14 * 24 * 60 * 60)
        var occurrences: [WidgetAlarmOccurrence] = []
        for alarm in alarms where alarm.isEnabled {
            var dates: [Date] = []
            if alarm.isRepeating {
                // Each repeat day this week and next.
                for day in alarm.repeatDays {
                    guard let first = alarm.nextFireDate(after: now, only: day) else { continue }
                    dates.append(first)
                    dates.append(first.addingTimeInterval(7 * 24 * 60 * 60))
                }
            } else if let next = alarm.oneShotFireDate ?? alarm.nextFireDate(after: now), next > now {
                dates.append(next)
            }
            for date in dates where date <= horizon {
                occurrences.append(WidgetAlarmOccurrence(
                    fireDate: date,
                    timeText: alarm.timeText,
                    periodText: alarm.periodText,
                    mission: alarm.mission.rawValue,
                    repeatText: alarm.repeatText,
                    placeLabel: alarm.isLocal ? nil : alarm.placeLabel
                ))
            }
        }
        occurrences.sort { $0.fireDate < $1.fireDate }

        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(Array(occurrences.prefix(40))) else { return }
        defaults.set(data, forKey: occurrencesKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
