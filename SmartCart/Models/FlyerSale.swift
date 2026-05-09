// FlyerSale.swift — SmartCart/Models/FlyerSale.swift

import Foundation

struct FlyerSale: Identifiable, Equatable {
    let id: Int64
    let itemID: Int64
    let storeID: Int64
    let salePrice: Double
    let regularPrice: Double?
    let validFrom: Date
    let validTo: Date?   // nil = Flipp didn't return valid_to; default +7 days was applied
    let source: String
    let fetchedAt: Date

    // Discount % vs. regularPrice. Falls back to nil if regularPrice is unknown.
    func discountPercent(fallbackRegularPrice: Double?) -> Double? {
        let reg = regularPrice ?? fallbackRegularPrice
        guard let reg = reg, reg > 0 else { return nil }
        return ((reg - salePrice) / reg) * 100
    }

    var isActiveToday: Bool {
        let today = Date()
        guard validFrom <= today else { return false }
        if let end = validTo { return end >= today }
        return true // no end date recorded — treat as active
    }
}
