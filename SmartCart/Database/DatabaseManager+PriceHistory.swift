// DatabaseManager+PriceHistory.swift
import Foundation
import SQLite

extension DatabaseManager {

    func insertPriceHistory(itemID: Int64, storeID: Int64, price: Double, source: String) {
        let today = Calendar.current.startOfDay(for: Date())
        let existing = priceHistoryTable.filter(
            priceHistItemID  == itemID  &&
            priceHistStoreID == storeID &&
            priceHistPrice   == price   &&
            priceHistDate    >= today
        )
        if (try? db.scalar(existing.count)) ?? 0 > 0 { return }
        _ = try? db.run(priceHistoryTable.insert(
            priceHistItemID  <- itemID,
            priceHistStoreID <- storeID,
            priceHistPrice   <- price,
            priceHistDate    <- Date(),
            priceHistSource  <- source
        ))
    }

    // All-stores version — kept intact for PriceHistoryView chart display.
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

    // P1-F: Store-scoped overload used by AlertEngine.evaluateAlerts().
    // Averages only rows matching the user's primary store for this item,
    // preventing a Walmart/Loblaws price blend from corrupting alert thresholds.
    func rollingAverage90(for itemID: Int64, storeID: Int64) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        let rows = try? db.prepare(
            priceHistoryTable
                .filter(
                    priceHistItemID  == itemID  &&
                    priceHistStoreID == storeID &&
                    priceHistDate    >= cutoff
                )
                .select(priceHistPrice)
        )
        let prices = rows?.compactMap { $0[priceHistPrice] } ?? []
        guard !prices.isEmpty else { return nil }
        return prices.reduce(0, +) / Double(prices.count)
    }

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

    func historicalLow(for itemID: Int64) -> (price: Double, label: String)? {
        let cal   = Calendar.current
        let today = Date()
        let month = cal.component(.month, from: today)
        let year  = cal.component(.year,  from: today)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        let startStr: String
        let endStr:   String
        let label:    String

        if month == 1 {
            startStr = "\(year - 1)-01-01"
            endStr   = "\(year - 1)-03-31"
            label    = "Based on last Jan\u{2013}Mar"
        } else {
            startStr = "\(year)-01-01"
            endStr   = fmt.string(from: today)
            label    = "Lowest this year"
        }

        guard let start = fmt.date(from: startStr),
              let end   = fmt.date(from: endStr) else { return nil }

        let phRows = try? db.prepare(
            priceHistoryTable
                .filter(priceHistItemID == itemID &&
                        priceHistDate   >= start  &&
                        priceHistDate   <= end)
                .select(priceHistPrice)
        )
        let phMin = phRows?.compactMap { $0[priceHistPrice] }.min()

        let purchRows = try? db.prepare(
            purchaseHistoryTable
                .filter(purchaseItemID == itemID &&
                        purchasedAt    >= start  &&
                        purchasedAt    <= end)
                .select(purchasePrice)
        )
        let purchMin = purchRows?.compactMap { $0[purchasePrice] }.min()

        let candidates = [phMin, purchMin].compactMap { $0 }
        guard let lowest = candidates.min() else { return nil }
        return (price: lowest, label: label)
    }
}
