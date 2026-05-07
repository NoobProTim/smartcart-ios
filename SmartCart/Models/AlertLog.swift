// AlertLog.swift — SmartCart/Models/AlertLog.swift
// One fired alert event. Maps to `alert_log`.
// Written BEFORE calling UNUserNotificationCenter so daily cap and dedup
// work correctly even when notification permission is denied.

import Foundation

struct AlertLog: Identifiable {
    let id: Int64
    let itemID: Int64
    let alertType: String       // "historical_low" | "sale" | "expiry"
    let triggerPrice: Double
    let firedAt: Date
    let notificationID: String? // nil when permission denied
}
