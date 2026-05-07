// DateHelper.swift — SmartCart/Utilities/DateHelper.swift
// Convenience date calculations used across the app.

import Foundation

enum DateHelper {

    /// Returns a human-readable string like "in 3 days" or "2 days ago".
    static func relativeDescription(from date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        switch days {
        case 0:          return "today"
        case 1:          return "tomorrow"
        case 2...:       return "in \(days) days"
        case -1:         return "yesterday"
        default:         return "\(-days) days ago"
        }
    }

    /// True if the given date is today.
    static func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Returns the start of today (midnight) as a Date.
    static func startOfToday() -> Date {
        Calendar.current.startOfDay(for: Date())
    }
}
