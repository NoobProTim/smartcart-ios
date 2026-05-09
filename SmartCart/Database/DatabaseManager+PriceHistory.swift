// DatabaseManager+PriceHistory.swift
// Extension on DatabaseManager for price_history reads and writes.
// Kept separate to avoid DatabaseManager.swift growing too large.

import Foundation
import SQLite

extension DatabaseManager {

    // Inserts a price_history row. Duplicate-suppression:
    // if an identical (item_id, store_id, price, date) row exists today, skip.
    func insertPriceHistory(itemID: Int64, storeID: Int64, price: Double, source: String) {
        let today = Calendar.current.startOfDay(for: Date())
        let existing = priceHistoryTable.filter(
            priceHistItemID  == itemID  &&
            priceHistStoreID == storeID &&
            priceHistPrice   == price   &&
            priceHistDate    >= today
        )
        if (try? db.scalar(existing.count)) ?? 0 > 0 { return }
        try? db.run(priceHistoryTable.insert(
            priceHistItemID  <- itemID,
            priceHistStoreID <- storeID,
            priceHistPrice   <- price,
            priceHistDate    <- Date(),
            priceHistSource  <- source
        ))
    }

    // 90-day rolling average price for an item across all selected stores.
    func rollingAverage90(for itemID: Int64) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let rows = try? db.prepare(
            priceHistoryTable
                .filter(priceHistItemID == itemID && priceHistDate >= cutoff)
                .select(priceHistPrice)
        )
        let prices = rows?.compactMap { $0[priceHistPrice] } ?? []
        guard !prices.isEmpty else { return nil }
        return prices.reduce(0, +) / Double(prices.count)
    }

    // Full price history for an item, newest first. Used by PriceHistoryViewModel.
    func fetchPriceHistory(for itemID: Int64) -> [PricePoint] {
        let rows = (try? db.prepare(
            priceHistoryTable
                .filter(priceHistItemID == itemID)
                .order(priceHistDate.desc)
        )) ?? AnySequence([])
        return rows.compactMap { row in
            guard let src = PriceSource(rawValue: row[priceHistSource]) else { return nil }
            return PricePoint(
                id:         row[priceHistID],
                itemID:     row[priceHistItemID],
                storeID:    row[priceHistStoreID],
                price:      row[priceHistPrice],
                observedAt: row[priceHistDate],
                source:     src
            )
        }
    }
}
