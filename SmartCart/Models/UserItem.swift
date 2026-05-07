// UserItem.swift — SmartCart/Models/UserItem.swift
// Join between user's tracked list and a canonical Item. Maps to `user_items`.
// Replenishment cycle priority: userOverrideCycleDays > inferredCycleDays > default (14d)

import Foundation

struct UserItem: Identifiable {
    let id: Int64
    let itemID: Int64
    let nameDisplay: String
    let lastPurchasedDate: Date?
    let lastPurchasedPrice: Double?
    let inferredCycleDays: Int?
    let userOverrideCycleDays: Int?
    let nextRestockDate: Date?
    let hasActiveAlert: Bool

    var effectiveCycleDays: Int {
        userOverrideCycleDays ?? inferredCycleDays ?? Constants.defaultReplenishmentDays
    }

    var isInRestockWindow: Bool {
        guard let restock = nextRestockDate else { return false }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: restock).day ?? Int.max
        return days <= Constants.restockWindowDays
    }
}
