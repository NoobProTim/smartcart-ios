// FlyerSale.swift — SmartCart/Models/FlyerSale.swift
// One sale or flyer event. Maps to `flyer_sales`.
// Rows are inserted with INSERT OR IGNORE (Fix P1-8) — unique index on
// (item_id, store_id, sale_start_date, sale_price) prevents duplicate rows
// from accumulating on every daily sync.

import Foundation

struct FlyerSale: Identifiable {
    let id: Int64
    let itemID: Int64
    let storeID: Int64
    let salePrice: Double
    let validFrom: Date
    let validTo: Date?    // nil when Flipp omitted valid_to; 7-day estimate applied
    let source: String    // "flipp" | "flipp_estimated_expiry" | "manual"
    let fetchedAt: Date

    // Percentage discount vs. the item's 90-day rolling average regular price.
    // Returns nil when averageRegularPrice is zero.
    func discountPercent(averageRegularPrice: Double) -> Double? {
        guard averageRegularPrice > 0 else { return nil }
        return ((averageRegularPrice - salePrice) / averageRegularPrice) * 100
    }

    // True when today falls within [validFrom, validTo].
    // If validTo is nil, active once started.
    var isActive: Bool {
        let now = Date()
        guard now >= validFrom else { return false }
        if let end = validTo { return now <= end }
        return true
    }

    // Days until sale expires. nil if validTo is nil. 0 if already ended.
    func expiresInDays() -> Int? {
        guard let end = validTo else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0)
    }
}
