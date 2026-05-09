// SettingsViewModel.swift — SmartCart/ViewModels/SettingsViewModel.swift
//
// Reads and writes user_settings through DatabaseManager.
// All setting properties use computed get/set backed by the DB.

import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {

    private let db = DatabaseManager.shared

    // Notification master toggle
    var notificationsEnabled: Bool {
        get { db.getSetting(key: "notification_enabled") == "1" }
        set { db.setSetting(key: "notification_enabled", value: newValue ? "1" : "0"); objectWillChange.send() }
    }

    // Alert sensitivity: "aggressive" | "balanced" | "conservative"
    var alertSensitivity: String {
        get { db.getSetting(key: "alert_sensitivity") ?? "balanced" }
        set { db.setSetting(key: "alert_sensitivity", value: newValue); objectWillChange.send() }
    }

    var quietHoursStart: String {
        get { db.getSetting(key: "quiet_hours_start") ?? "22:00" }
        set { db.setSetting(key: "quiet_hours_start", value: newValue); objectWillChange.send() }
    }

    var quietHoursEnd: String {
        get { db.getSetting(key: "quiet_hours_end") ?? "08:00" }
        set { db.setSetting(key: "quiet_hours_end", value: newValue); objectWillChange.send() }
    }

    // Sale alert toggles (CR-001)
    var saleAlertsEnabled: Bool {
        get { db.getSetting(key: "sale_alerts_enabled") == "1" }
        set { db.setSetting(key: "sale_alerts_enabled", value: newValue ? "1" : "0"); objectWillChange.send() }
    }

    var flyerExpiryReminderEnabled: Bool {
        get { db.getSetting(key: "flyer_expiry_reminder") == "1" }
        set { db.setSetting(key: "flyer_expiry_reminder", value: newValue ? "1" : "0"); objectWillChange.send() }
    }

    // 1 | 2 | 3 days before sale ends
    var expiryReminderDaysBefore: Int {
        get { Int(db.getSetting(key: "expiry_reminder_days_before") ?? "1") ?? 1 }
        set { db.setSetting(key: "expiry_reminder_days_before", value: String(newValue)); objectWillChange.send() }
    }

    // Suppress sale alerts when item is outside restock window
    var saleAlertRestockOnly: Bool {
        get { db.getSetting(key: "sale_alert_restock_only") == "1" }
        set { db.setSetting(key: "sale_alert_restock_only", value: newValue ? "1" : "0"); objectWillChange.send() }
    }

    // Minimum discount % to trigger a sale alert: 0 | 10 | 20 | 30
    var minDiscountThreshold: Int {
        get { Int(db.getSetting(key: "min_discount_threshold") ?? "0") ?? 0 }
        set { db.setSetting(key: "min_discount_threshold", value: String(newValue)); objectWillChange.send() }
    }

    var postalCode: String {
        get { db.getSetting(key: "user_postal_code") ?? "" }
        set { db.setSetting(key: "user_postal_code", value: newValue.isEmpty ? nil : newValue); objectWillChange.send() }
    }
}
