// FlyerSale.swift — SmartCart/Models/FlyerSale.swift
// One sale or flyer event. Maps to `flyer_sales`.

import Foundation

struct FlyerSale: Identifiable {
    let id: Int64
    let itemID: Int64
    let storeID: Int64
    let salePrice: Double
    let validFrom: Date
    let validTo: Date?
    let source: String
    let fetchedAt: Date

    func discountPercent(averageRegularPrice: Double) -> Double? {
        guard averageRegularPrice > 0 else { return nil }
        return ((averageRegularPrice - salePrice) / averageRegularPrice) * 100
    }

    var isActive: Bool {
        let now = Date()
        guard now >= validFrom else { return false }
        if let end = validTo { return now <= end }
        return true
    }

    func expiresInDays() -> Int? {
        guard let end = validTo else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
    }
}
