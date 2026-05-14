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
    static let defaultReplenishmentDays: Int = 14
    static let minReplenishmentDays: Int = 3
    static let maxReplenishmentDays: Int = 180
    /// Minimum purchases required before trusting the inferred median cycle.
    static let inferenceMinPurchases: Int = 3
    static let restockWindowDays: Int = 3

    // MARK: - Alerts
    /// Maximum alerts per day — enforced by counting alert_log rows for today.
    /// Use DatabaseManager.alertsFiredToday(). Do NOT read from user_settings.
    static let dailyAlertCap: Int = 3
    static let maxAlertsPerWeek: Int = 10
    static let saleExpiryReminderDays: Int = 1

    // MARK: - Price Thresholds
    static let historicalLowThreshold: Double = 0.85
    static let trendLowUpperBound: Double = 0.85
    static let trendAboveAverageLower: Double = 1.10

    // MARK: - Price Matching
    static let flippMatchThreshold: Double = 0.5
    static let flippEstimatedSaleExpiryDays: Int = 7

    // MARK: - Background Sync
    static let backgroundTaskID = "com.smartcart.app.pricerefresh"
    static let refreshStalenessThreshold: TimeInterval = 3600
    static let minRefreshIntervalSeconds: TimeInterval = 3600

    // MARK: - Price History
    static let rollingAverageDays: Int = 90

    // MARK: - OCR
    static let ocrConfidenceThreshold: Float = 0.6

    // MARK: - Onboarding
    static let canadianPostalCodeRegex = "^[A-Za-z]\\d[A-Za-z][ -]?\\d[A-Za-z]\\d$"
}
