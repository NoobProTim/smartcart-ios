// DatabaseManager+Insights.swift
// SmartCart
//
// SQLite read methods used exclusively by InsightsViewModel.
// All methods are synchronous and safe to call from a background Task.
// Uses the same SQLite.swift db connection as other DatabaseManager extensions.

import Foundation
import SQLite

extension DatabaseManager {

    // MARK: - Spend totals

    /// Returns total price paid for all purchases where purchased_at is
    /// between `start` and `end`. Returns 0 on error or no data.
    func totalSpend(from start: Date, to end: Date) -> Double {
        let table = Table("purchase_history")
        let price = Expression<Double>("price")
        let purchasedAt = Expression<Date>("purchased_at")

        do {
            let query = table
                .filter(purchasedAt >= start && purchasedAt <= end)
                .select(price.sum)
            return try db.scalar(query) ?? 0.0
        } catch {
            print("[DatabaseManager+Insights] totalSpend error: \(error)")
            return 0.0
        }
    }

    // MARK: - Purchases in range

    /// Returns lightweight purchase rows joined with user_items names.
    /// Used by the savings calculation in InsightsViewModel.
    func purchasesInRange(from start: Date, to end: Date) -> [InsightPurchaseRow] {
        let purchases = Table("purchase_history")
        let userItems = Table("user_items")

        let itemIDCol     = Expression<Int64>("item_id")
        let priceCol      = Expression<Double>("price")
        let purchasedAtCol = Expression<Date>("purchased_at")
        let nameCol       = Expression<String>("name")
        let idCol         = Expression<Int64>("id")

        do {
            let query = purchases
                .join(userItems, on: userItems[idCol] == purchases[itemIDCol])
                .filter(purchasedAtCol >= start && purchasedAtCol <= end)
                .select(purchases[itemIDCol], priceCol, userItems[nameCol])

            return try db.prepare(query).map { row in
                InsightPurchaseRow(
                    itemID: row[purchases[itemIDCol]],
                    itemName: row[userItems[nameCol]],
                    price: row[priceCol]
                )
            }
        } catch {
            print("[DatabaseManager+Insights] purchasesInRange error: \(error)")
            return []
        }
    }

    // MARK: - Rolling average

    /// Returns the mean price paid for `itemID` in the last `days` days.
    /// Reads purchase_history (real receipts), not price_history (flyer data).
    func rollingAveragePrice(itemID: Int64, days: Int) -> Double {
        guard let since = Calendar.current.date(
            byAdding: .day, value: -days, to: Date()
        ) else { return 0 }

        let table = Table("purchase_history")
        let price = Expression<Double>("price")
        let itemIDCol = Expression<Int64>("item_id")
        let purchasedAt = Expression<Date>("purchased_at")

        do {
            let query = table
                .filter(itemIDCol == itemID && purchasedAt >= since && price > 0)
                .select(price.average)
            return try db.scalar(query) ?? 0.0
        } catch {
            print("[DatabaseManager+Insights] rollingAveragePrice error: \(error)")
            return 0.0
        }
    }

    // MARK: - Spend by store

    /// Returns [storeName: totalSpend] for purchases in the given date range.
    func spendByStore(from start: Date, to end: Date) -> [String: Double] {
        let table = Table("purchase_history")
        let storeCol = Expression<String?>("store_name")
        let priceCol = Expression<Double>("price")
        let purchasedAtCol = Expression<Date>("purchased_at")

        do {
            var result: [String: Double] = [:]
            for row in try db.prepare(
                table.filter(purchasedAtCol >= start && purchasedAtCol <= end)
            ) {
                let store = row[storeCol] ?? "Other"
                result[store, default: 0] += row[priceCol]
            }
            return result
        } catch {
            print("[DatabaseManager+Insights] spendByStore error: \(error)")
            return [:]
        }
    }

    // MARK: - Average price in date window

    /// Returns the mean price for `itemID` in price_history between `start` and `end`.
    /// Used by the rising prices calculation (compares two 90-day windows).
    func averagePrice(itemID: Int64, from start: Date, to end: Date) -> Double {
        let table = Table("price_history")
        let priceCol = Expression<Double>("price")
        let itemIDCol = Expression<Int64>("item_id")
        let recordedAtCol = Expression<Date>("recorded_at")

        do {
            let query = table
                .filter(
                    itemIDCol == itemID
                    && recordedAtCol >= start
                    && recordedAtCol <= end
                    && priceCol > 0
                )
                .select(priceCol.average)
            return try db.scalar(query) ?? 0.0
        } catch {
            print("[DatabaseManager+Insights] averagePrice error: \(error)")
            return 0.0
        }
    }

    // MARK: - All user items (lightweight)

    /// Returns every row in user_items as a minimal struct.
    /// Used by the rising prices loop — does not load purchase or price history.
    func fetchAllUserItems() -> [InsightItemRow] {
        let table = Table("user_items")
        let idCol = Expression<Int64>("id")
        let nameCol = Expression<String>("name")

        do {
            return try db.prepare(table).map { row in
                InsightItemRow(itemID: row[idCol], name: row[nameCol])
            }
        } catch {
            print("[DatabaseManager+Insights] fetchAllUserItems error: \(error)")
            return []
        }
    }
}

// MARK: - Lightweight row types (Insights-only)

/// Minimal purchase record used only by InsightsViewModel.
struct InsightPurchaseRow {
    let itemID: Int64
    let itemName: String
    let price: Double
}

/// Minimal user item record used only by InsightsViewModel.
struct InsightItemRow {
    let itemID: Int64
    let name: String
}
