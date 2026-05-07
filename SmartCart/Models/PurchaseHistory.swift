// PurchaseHistory.swift — SmartCart/Models/PurchaseHistory.swift
// One confirmed purchase event. Maps to `purchase_history`.
// Always written via DatabaseManager.markPurchased() — never insert directly.

import Foundation

struct PurchaseHistory: Identifiable {
    let id: Int64
    let itemID: Int64
    let purchasedAt: Date
    let price: Double?    // nil when price was unknown at confirmation time
    let source: String    // "receipt" | "manual" only
    let storeID: Int64?   // nil for manual entries without store selection
}
