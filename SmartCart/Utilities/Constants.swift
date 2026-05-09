// Constants.swift — SmartCart/Utilities/Constants.swift
//
// App-wide tuneable values. Change these to adjust app behaviour without
// hunting for magic numbers across multiple files.
//
// Naming convention: all Constants are static lets on the Constants enum.

import Foundation

enum Constants {

    // MARK: - Replenishment

    // Days used as the default restock cycle when no purchase history exists.
    // Covers most weekly or biweekly grocery shoppers.
    static let defaultReplenishmentDays = 14

    // An item is considered “in its restock window” when its next restock date
    // is within this many days from today. Drives pin-to-top on the Smart List.
    static let restockWindowDays = 3

    // MARK: - Alert caps

    // Maximum push notifications fired per day across ALL items.
    // Prevents notification fatigue. See AlertEngine.evaluateAlerts().
    static let maxAlertsPerDay = 5

    // MARK: - Price thresholds

    // An item’s current price must be at or below this fraction of its 90-day
    // rolling average to be classified as a “historical low”.
    // 0.85 = must be 15% or more below the rolling average.
    static let historicalLowThreshold: Double = 0.85

    // Fraction bounds used in ItemDetailView trend indicator.
    // ≤ 0.85 × avg  → “Low” (green)
    // 0.85 – 1.10 × avg → “Near average” (yellow)
    // > 1.10 × avg  → “Above average” (red)
    static let trendLowUpperBound:     Double = 0.85
    static let trendAboveAverageLower: Double = 1.10

    // MARK: - Sync

    // Pull-to-refresh is blocked unless the last sync was more than this many
    // seconds ago. 3600 = 1 hour.
    static let minRefreshIntervalSeconds: TimeInterval = 3600

    // MARK: - Onboarding

    // Canadian postal code regex. Matches A1A 1A1 format (with or without space).
    static let canadianPostalCodeRegex = "^[A-Za-z]\\d[A-Za-z][ -]?\\d[A-Za-z]\\d$"

    // MARK: - Flipp

    // Number of days to estimate a sale end date when Flipp omits valid_to.
    static let flippEstimatedSaleExpiryDays = 7

    // MARK: - Background sync

    // Background task identifier — must match Info.plist BGTaskSchedulerPermittedIdentifiers.
    static let backgroundTaskID = "com.smartcart.app.pricerefresh"
}
