// PurchaseRecord.swift — SmartCart/Models/PurchaseRecord.swift

import Foundation

enum PurchaseSource: String {
    case receipt
    case manual
}

struct PurchaseRecord: Identifiable {
    let id: Int64
    let itemID: Int64
    let storeID: Int64?
    let price: Double?
    let purchasedAt: Date
    let source: PurchaseSource
}
