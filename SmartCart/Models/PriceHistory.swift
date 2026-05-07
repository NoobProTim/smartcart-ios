// PriceHistory.swift — SmartCart/Models/PriceHistory.swift
// One regular shelf-price observation. Maps to `price_history`.
// IMPORTANT: Regular prices ONLY. Sale prices belong in FlyerSale.

import Foundation

struct PriceHistory: Identifiable {
    let id: Int64
    let itemID: Int64
    let storeID: Int64
    let price: Double
    let observedAt: Date
    let source: String    // "flipp" | "manual"
}
