// Constants.swift — SmartCart/Utilities/Constants.swift
// All magic numbers live here. Change a value once, it updates everywhere.
// NOTE: Daily alert cap is enforced by counting alert_log rows where fired_at = today.
// Do NOT track separately in user_settings.

import Foundation

enum Constants {
    static let defaultReplenishmentDays   = 14    // Used when < 2 purchases exist
    static let restockWindowDays          = 3     // Days before nextRestockDate to pin item to top
    static let historicalLowThreshold     = 0.85  // Alert fires when price ≤ avg × this
    static let dailyAlertCap              = 3     // Max push notifications per day
    static let ocrConfidenceGate          = 0.85  // Min Vision confidence to auto-include item
    static let rollingAverageDays         = 90    // Window for price history rolling average
    static let manualRefreshCooldownHours = 1     // Pull-to-refresh won't hit network if fresher
    static let flyerSaleExpiryFallbackDays = 7    // Assumed sale length when Flipp omits valid_to
    static let flippMatchThreshold        = 0.5   // Min token-overlap score to accept Flipp price match
}
