// Constants.swift
// SmartCart — Services/Constants.swift
//
// Single place for all app-wide configuration values.
// WHY: Scattered magic numbers are a maintenance trap. Changing any threshold
// (e.g. raising the daily alert cap from 3 to 5) should be a one-line edit here,
// not a search-and-replace across the codebase.
//
// UPDATED IN TASK #3 (P1-2):
// Added plain-English comment clarifying that the daily alert cap is enforced
// by counting alert_log rows — NOT by user_settings counters.
// Added flippMatchThreshold (P1-1) and restockWindowDays.

import Foundation

enum Constants {

    // MARK: - Replenishment
    /// Default replenishment cycle when the user has set no override
    /// and the item has fewer than 2 purchases (not enough data to infer).
    static let defaultReplenishmentDays: Int = 14

    /// An item is "in restock window" when its next restock date is
    /// this many days away or fewer. Controls pin-to-top on the Smart List.
    static let restockWindowDays: Int = 3

    // MARK: - Alerts
    /// Maximum alerts that can fire per day across all items.
    ///
    /// ⚠️ IMPORTANT — SINGLE SOURCE OF TRUTH:
    /// The daily alert cap is enforced by counting rows in the alert_log table
    /// where fired_at falls on today's date (see DatabaseManager.alertsFiredToday()).
    /// Do NOT track this separately in user_settings (daily_alert_count / daily_alert_date).
    /// Those fields have been removed from Schema.defaultSettings.
    /// Any code reading daily_alert_count from user_settings will always get NULL
    /// and will silently bypass the cap. Use alertsFiredToday() — nothing else.
    static let dailyAlertCap: Int = 3

    /// Number of days before a sale expires to send an Expiry Reminder (Type C).
    static let saleExpiryReminderDays: Int = 1

    // MARK: - Price Matching
    /// Minimum token-overlap score required to write a Flipp result's price
    /// to price_history for a given item. Prevents cross-SKU contamination.
    /// Range: 0.0 (any match) → 1.0 (exact token match required).
    /// 0.5 means at least half the tokens must overlap.
    static let flippMatchThreshold: Double = 0.5

    // MARK: - Background Sync
    /// Pull-to-refresh will not trigger a network sync if the last refresh
    /// happened fewer than this many seconds ago.
    static let refreshStalenessThreshold: TimeInterval = 3600 // 1 hour

    // MARK: - Price History
    /// Rolling window for the average regular price calculation.
    static let rollingAverageDays: Int = 90

    // MARK: - OCR
    /// Minimum Vision confidence score for a text observation to be kept.
    static let ocrConfidenceThreshold: Float = 0.6
}
