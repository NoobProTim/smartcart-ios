// DateHelper.swift — SmartCart/Utilities/DateHelper.swift
//
// Single place for Date <→ String conversions used throughout the app.
// All dates are stored in SQLite as ISO 8601 strings (UTC).
// Using one formatter everywhere prevents silent format mismatches between layers.

import Foundation

enum DateHelper {

    // ISO 8601 formatter — used for all DB reads and writes.
    // DateFormatter is expensive to create; reuse this instance everywhere.
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Formatter for “today” comparisons — date-only, no time component.
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    // Converts a Date to an ISO 8601 string for SQLite storage.
    static func string(from date: Date) -> String {
        iso8601.string(from: date)
    }

    // Converts an ISO 8601 string back to a Date. Returns nil on parse failure.
    static func date(from string: String) -> Date? {
        iso8601.date(from: string)
    }

    // Returns the current UTC timestamp as an ISO 8601 string.
    // Used for created_at, fired_at, fetched_at columns.
    static func nowString() -> String {
        string(from: Date())
    }

    // Returns today’s date as "yyyy-MM-dd" in the local timezone.
    // Used for “alerts fired today” queries in DatabaseManager.
    static func todayString() -> String {
        dateOnly.string(from: Date())
    }

    // Formats a Date for display in the UI (e.g. “May 7”).
    static func displayString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    // Returns the number of days from today to a future date.
    // Negative values mean the date is in the past.
    static func daysFrom(now to: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Date(), to: to).day ?? 0
    }

    // Formats a Date for user-facing display (e.g. "May 14, 2026").
    static func friendlyDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
