// DatabaseManager+Fixes.swift
// SmartCart — Database/DatabaseManager+Fixes.swift
//
// P1-E fixes + DB helpers for ReplenishmentEngine.
//
// REPLENISHMENT DELEGATION (BLOCKER-1 fix — Task #6):
//   recalculateReplenishment() now explicitly branches on quantity:
//     quantity == 1  → ReplenishmentEngine.shared.recalculate(for:)
//                      Standard single-unit path. No scaling needed.
//                      This is the call PRISM required at BLOCKER-1.
//     quantity  > 1  → ReplenishmentEngine.shared.updateOnPurchase(itemID:quantity:)
//                      Quantity-scaling path (P2-4). Defers to engine.
//
//   Previously the shim called updateOnPurchase() for ALL quantities.
//   updateOnPurchase() internally routes qty==1 → recalculate(), so behaviour
//   was equivalent — but PRISM correctly flagged that the single-unit path
//   should call recalculate(for:) directly, making the delegation explicit
//   and readable at the shim level.
//
//   DatabaseManager is data-only — it reads and writes rows.
//   ReplenishmentEngine owns all cycle inference and date calculation.
//
//   Call chain after this fix:
//     markPurchased()        → recalculateReplenishment(qty:1)  → engine.recalculate(for:)
//     markPurchased(qty:N)   → recalculateReplenishment(qty:N)  → engine.updateOnPurchase()
//     markPurchasedOnDate()  → recalculateReplenishment(qty:1)  → engine.recalculate(for:)

import Foundation
import SQLite

extension DatabaseManager {

    // MARK: - markPurchased(itemID:priceAtPurchase:quantity:)
    // Atomically writes a purchase to purchase_history and updates user_items.
    // quantity > 1 means the user bought multiple units in one transaction.
    // After the DB write, delegates replenishment recalculation to ReplenishmentEngine.
    func markPurchased(itemID: Int64, priceAtPurchase: Double?, quantity: Int = 1) {
        let today = Date()
        let qty   = max(1, quantity)
        do {
            try db.transaction {
                let userItem = userItemsTable.filter(userItemsItemID == itemID)
                try db.run(userItem.update(
                    userItemsLastPurchasedDate  <- today,
                    userItemsLastPurchasedPrice <- priceAtPurchase,
                    userItemsNextRestockDate    <- nil   // engine will set the real value below
                ))
                try db.run(purchaseHistoryTable.insert(
                    purchaseItemID  <- itemID,
                    purchasedAt     <- today,
                    purchasePrice   <- priceAtPurchase,
                    purchaseQty     <- Int64(qty)
                ))
            }
            // Delegate all replenishment math to ReplenishmentEngine.
            // DO NOT put cycle inference here — engine owns that logic.
            recalculateReplenishment(itemID: itemID, quantity: qty)
            updateSeasonalFlag(itemID: itemID)
        } catch {
            print("[DatabaseManager] markPurchased failed for itemID \(itemID): \(error)")
        }
    }

    // MARK: - recalculateReplenishment(itemID:quantity:)
    // BLOCKER-1 fix (Task #6):
    //   Single-unit purchases (qty == 1) now call recalculate(for:) directly.
    //   This is the explicit delegation path PRISM required.
    //   Multi-unit purchases (qty > 1) still call updateOnPurchase() so that
    //   quantity scaling (P2-4) is applied — the scaled restock date is only
    //   computed inside updateOnPurchase().
    //
    // WHY KEEP THIS WRAPPER:
    //   markPurchasedOnDate() in DatabaseManager+Purchases.swift calls it by name.
    //   Keeping the wrapper means that file needs no change.
    func recalculateReplenishment(itemID: Int64, quantity: Int) {
        if quantity <= 1 {
            // Standard single-unit path — call recalculate(for:) directly.
            // PRISM BLOCKER-1 required this explicit delegation.
            ReplenishmentEngine.shared.recalculate(for: itemID)
        } else {
            // Bulk purchase path — updateOnPurchase() applies quantity scaling (P2-4).
            ReplenishmentEngine.shared.updateOnPurchase(itemID: itemID, quantity: quantity)
        }
    }

    // MARK: - updateSeasonalFlag(itemID:)
    // Reads all purchase dates; if stddev of inter-purchase gaps > 30 days
    // across >= 3 purchases, marks the item as seasonal in user_items.
    // Seasonal items have restock alerts suppressed.
    private func updateSeasonalFlag(itemID: Int64) {
        let rows = (try? db.prepare(
            purchaseHistoryTable
                .filter(purchaseItemID == itemID)
                .order(purchasedAt.asc)
                .select(purchasedAt)
        )) ?? AnySequence([])

        let dates = rows.compactMap { $0[purchasedAt] }
        guard dates.count >= 3 else { return }

        var gaps: [Double] = []
        for i in 1 ..< dates.count {
            let diff = dates[i].timeIntervalSince(dates[i - 1]) / 86400
            gaps.append(diff)
        }
        let mean   = gaps.reduce(0, +) / Double(gaps.count)
        let stddev = sqrt(gaps.map { pow($0 - mean, 2) }.reduce(0, +) / Double(gaps.count))

        let isSeasonal = stddev > 30
        try? db.run(
            userItemsTable
                .filter(userItemsItemID == itemID)
                .update(userItemsIsSeasonal <- (isSeasonal ? 1 : 0))
        )
    }

    // MARK: - fetchUserItem(itemID:)
    // Fetches a single UserItem by its item_id.
    // Used by ReplenishmentEngine to read cycle + seasonal data without
    // loading the entire list. Returns nil if the item doesn't exist.
    func fetchUserItem(itemID: Int64) -> UserItem? {
        let query = userItemsTable
            .join(itemsTable, on: userItemsItemID == self.itemID)
            .filter(userItemsItemID == itemID)
            .limit(1)
        guard let row = try? db.pluck(query) else { return nil }
        return UserItem(
            id: row[userItemID],
            itemID: row[userItemsItemID],
            nameDisplay: row[itemNameDisplay],
            lastPurchasedDate: row[userItemsLastPurchasedDate],
            lastPurchasedPrice: row[userItemsLastPurchasedPrice],
            inferredCycleDays: row[userItemsReplenishInferred].map { Int($0) },
            userOverrideCycleDays: row[userItemsReplenishOverride].map { Int($0) },
            nextRestockDate: row[userItemsNextRestockDate],
            hasActiveAlert: hasAlertFiredForItem(itemID: itemID),
            isSeasonal: (row[userItemsIsSeasonal] ?? 0) == 1
        )
    }

    // MARK: - setNextRestockDate(itemID:date:)
    // Directly sets the next_restock_date for an item.
    // Called by ReplenishmentEngine after computing the restock date.
    func setNextRestockDate(itemID: Int64, date: Date?) {
        try? db.run(
            userItemsTable
                .filter(userItemsItemID == itemID)
                .update(userItemsNextRestockDate <- date)
        )
    }

    // MARK: - fetchCycleDays(for:)
    // RAW DATA READ ONLY — no inference logic here.
    // Reads purchase_history and returns the raw median gap between purchases.
    // ReplenishmentEngine.inferCycleDays() calls this to get raw intervals,
    // then applies its own threshold + median + clamping logic on top.
    //
    // Returns nil if fewer than 2 purchases exist.
    func fetchCycleDays(for itemID: Int64) -> Int? {
        let rows = (try? db.prepare(
            purchaseHistoryTable
                .filter(purchaseItemID == itemID)
                .order(purchasedAt.asc)
        )) ?? AnySequence([])
        let dates = rows.compactMap { $0[purchasedAt] as Date? }
        guard dates.count >= 2 else { return nil }
        var intervals: [Int] = []
        for i in 1 ..< dates.count {
            let days = Calendar.current.dateComponents([.day], from: dates[i - 1], to: dates[i]).day ?? 0
            if days > 0 { intervals.append(days) }
        }
        guard !intervals.isEmpty else { return nil }
        let sorted = intervals.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - updateReplenishmentData(itemID:inferredCycleDays:nextRestockDate:)
    // Writes the engine's computed values back to user_items.
    // Called by ReplenishmentEngine.recalculate(for:) after inference is complete.
    func updateReplenishmentData(itemID: Int64, inferredCycleDays: Int?, nextRestockDate: Date?) {
        let inferred: Int64? = inferredCycleDays.map { Int64($0) }
        try? db.run(
            userItemsTable
                .filter(userItemsItemID == itemID)
                .update(
                    userItemsReplenishInferred  <- inferred,
                    userItemsNextRestockDate    <- nextRestockDate
                )
        )
    }

    // MARK: - hasActiveAlert(for:)
    // Public alias used by ReplenishmentEngine.urgencyScore() for band-1 check.
    // Returns true if an alert fired for this item today.
    func hasActiveAlert(for itemID: Int64) -> Bool {
        return hasAlertFiredForItem(itemID: itemID)
    }

    // MARK: - insertFlyerSale (P1-G race-condition-safe upsert)
    func insertFlyerSale(itemID: Int64, storeID: Int64, salePrice: Double,
                         startDate: Date, endDate: Date?, source: String) {
        let sql = """
            INSERT INTO flyer_sales
                (item_id, store_id, sale_price, sale_start_date, sale_end_date, source, fetched_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_id, store_id, sale_start_date) DO UPDATE SET
                fetched_at = excluded.fetched_at,
                sale_price = excluded.sale_price,
                sale_end_date = excluded.sale_end_date
        """
        let fmt    = ISO8601DateFormatter()
        let endVal: String? = endDate.map { fmt.string(from: $0) }
        try? db.execute(
            sql,
            itemID,
            storeID,
            salePrice,
            fmt.string(from: startDate),
            endVal as Any,
            source,
            fmt.string(from: Date())
        )
    }

    // MARK: - applyFlyerSalesUniqueIndex
    // Migration helper — called inside runMigrations().
    func applyFlyerSalesUniqueIndex() {
        try? db.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_flyer_unique
            ON flyer_sales(item_id, store_id, sale_start_date)
        """)
    }

    // MARK: - hasAlertFiredForItem(itemID:)
    // Returns true if an alert fired for this item today.
    // Used by fetchUserItems() and hasActiveAlert() to set hasActiveAlert on UserItem.
    func hasAlertFiredForItem(itemID: Int64) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let count = (try? db.scalar(
            alertLogTable.filter(alertItemID == itemID && alertFiredAt >= startOfToday).count
        )) ?? 0
        return count > 0
    }
}
