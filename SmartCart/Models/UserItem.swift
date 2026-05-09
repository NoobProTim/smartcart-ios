// UserItem.swift — SmartCart/Models/UserItem.swift
// Join between user's tracked list and a canonical Item. Maps to `user_items`.
// Replenishment cycle priority: userOverrideCycleDays > inferredCycleDays > default (14d)

import Foundation

struct UserItem: Identifiable {
    let id: Int64
    let itemID: Int64
    let nameDisplay: String          // Convenience copy from joined Item
    let lastPurchasedDate: Date?
    let lastPurchasedPrice: Double?
    let inferredCycleDays: Int?      // Median interval from purchase_history; nil if < 2 purchases
    let userOverrideCycleDays: Int?  // User-set in Settings; always wins when present
    let nextRestockDate: Date?       // = lastPurchasedDate + effectiveCycleDays
    let hasActiveAlert: Bool         // True if alert_log has a row for this item today

    // The cycle used for all replenishment calculations.
    var effectiveCycleDays: Int {
        userOverrideCycleDays ?? inferredCycleDays ?? Constants.defaultReplenishmentDays
    }

    // True when nextRestockDate is within Constants.restockWindowDays.
    // Drives pin-to-top on the Smart List.
    var isInRestockWindow: Bool {
        guard let restock = nextRestockDate else { return false }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: restock).day ?? Int.max
        return days <= Constants.restockWindowDays
    }
}
