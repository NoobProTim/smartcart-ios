// Constants.swift — SmartCart/Utilities/Constants.swift
import Foundation

enum Constants {

    // MARK: - Replenishment
    static let defaultReplenishmentDays = 14
    static let restockWindowDays = 3

    // MARK: - Alert caps
    static let maxAlertsPerDay   = 5
    // P1-A: weekly cap prevents maxAlertsPerDay × 7 flood across a large item list
    static let maxAlertsPerWeek  = 10

    // MARK: - Price thresholds
    static let historicalLowThreshold: Double = 0.85
    static let trendLowUpperBound:     Double = 0.85
    static let trendAboveAverageLower: Double = 1.10

    // MARK: - Sync
    static let minRefreshIntervalSeconds: TimeInterval = 3600

    // MARK: - Onboarding
    static let canadianPostalCodeRegex = "^[A-Za-z]\\d[A-Za-z][ -]?\\d[A-Za-z]\\d$"

    // MARK: - Flipp
    static let flippEstimatedSaleExpiryDays = 7

    // MARK: - Background sync
    static let backgroundTaskID = "com.smartcart.app.pricerefresh"
}
