// PurchaseHistory.swift — SmartCart/Models/PurchaseHistory.swift
// One confirmed purchase event. Maps to `purchase_history`.
// Always written via DatabaseManager.markPurchased() — never insert directly.

import Foundation

struct PurchaseHistory: Identifiable {
    let id: Int64
    let itemID: Int64
    let purchasedAt: Date
    let price: Double?
    let source: String    // "receipt" | "manual" only
    let storeID: Int64?
}
