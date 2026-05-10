// UserItem.swift — SmartCart/Models/UserItem.swift
//
// The Swift representation of one row that joins user_items + items.
// All fields map 1-to-1 with the DB columns defined in Schema.swift.
// Computed properties live here to keep DB and UI logic separate.

import Foundation

struct UserItem: Identifiable, Equatable {
    let id: Int64
    let itemID: Int64
    let nameDisplay: String
    let lastPurchasedDate: Date?
    let lastPurchasedPrice: Double?
    let inferredCycleDays: Int?
    let userOverrideCycleDays: Int?
    let nextRestockDate: Date?
    /// True when at least one alert for this item fired today. (Fix P1-5)
    let hasActiveAlert: Bool
    /// True when the item's purchase pattern is too irregular to predict.
    /// Set automatically by seasonal detection in DatabaseManager+Fixes.
    /// When true, ReplenishmentEngine suppresses all restock nudges.
    let isSeasonal: Bool

    // MARK: - Computed helpers

    /// The cycle length the app actually uses:
    /// user override takes precedence over the inferred value.
    var effectiveCycleDays: Int? {
        userOverrideCycleDays ?? inferredCycleDays
    }

    /// How many days until (or since) the next suggested restock.
    /// Negative = overdue.
    var daysUntilRestock: Int? {
        guard let next = nextRestockDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: next).day
    }

    /// True when the item is inside its restock window.
    /// Delegates to the half-cycle formula used in ReplenishmentEngine
    /// so the logic stays consistent everywhere.
    var isInRestockWindow: Bool {
        guard let last  = lastPurchasedDate,
              let cycle = effectiveCycleDays,
              cycle >= 2,               // guard against bogus data
              !isSeasonal else { return false }
        let halfCycle  = Double(cycle) * 0.5
        let windowOpen = last.addingTimeInterval(halfCycle * 86_400)
        return Date() >= windowOpen
    }
}
