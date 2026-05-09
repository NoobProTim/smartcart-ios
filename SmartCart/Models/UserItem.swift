// UserItem.swift — SmartCart/Models/UserItem.swift

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
    // True when at least one alert for this item fired today.
    // Populated by DatabaseManager.hasAlertFiredForItem(). Fix P1-5.
    let hasActiveAlert: Bool

    // The cycle length the app actually uses:
    // user override takes precedence over the inferred value.
    var effectiveCycleDays: Int? {
        userOverrideCycleDays ?? inferredCycleDays
    }

    // How many days until (or since) the next suggested restock.
    // Negative = overdue.
    var daysUntilRestock: Int? {
        guard let next = nextRestockDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: next).day
    }

    // True when the item is inside its restock window:
    // today >= last_purchased_date + (cycle * 0.5)
    var isInRestockWindow: Bool {
        guard let last = lastPurchasedDate,
              let cycle = effectiveCycleDays else { return false }
        let halfCycle = Double(cycle) * 0.5
        let windowOpen = last.addingTimeInterval(halfCycle * 86_400)
        return Date() >= windowOpen
    }
}
