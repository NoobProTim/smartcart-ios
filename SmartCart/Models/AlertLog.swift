// AlertLog.swift — SmartCart/Models/AlertLog.swift
// One fired alert event. Maps to `alert_log`.
// Written BEFORE calling UNUserNotificationCenter so daily cap and dedup
// work correctly even when notification permission is denied.

import Foundation

struct AlertLog: Identifiable {
    let id: Int64
    let itemID: Int64
    let storeID: Int64          // 0 = no store recorded
    let alertType: String       // "historical_low" | "sale" | "expiry" | "combined"
    let triggerPrice: Double    // The price that caused this alert to fire
    let firedAt: Date
    let notificationID: String? // "alert-{type}-{itemID}"; nil when permission denied
    let saleEventID: Int64?     // Links to flyer_sales.id for sale/expiry alerts
}
