// DatabaseManager+Fixes.swift
// Task #1 P1-E fixes + Task #2 DB helpers for ReplenishmentEngine.
import Foundation
import SQLite

extension DatabaseManager {

    // MARK: - P1-E: Atomic purchase write with quantity awareness
    // quantity > 1 scales the next-restock date forward proportionally.
    // Seasonal detection: if stddev of inter-purchase gaps > 30 days across ≥ 3
    // purchases, sets user_items.is_seasonal = true and suppresses restock alerts.
    func markPurchased(itemID: Int64, priceAtPurchase: Double?, quantity: Int = 1) {
        let today = Date()
        let qty   = max(1, quantity)
        do {
            try db.transaction {
                let userItem = userItemsTable.filter(userItemsItemID == itemID)
                try db.run(userItem.update(
                    userItemsLastPurchasedDate  <- today,
                    userItemsLastPurchasedPrice <- priceAtPurchase,
                    userItemsNextRestockDate    <- nil
                ))
                try db.run(purchaseHistoryTable.insert(
                    purchaseItemID  <- itemID,
                    purchasedAt     <- today,
                    purchasePrice   <- priceAtPurchase,
                    purchaseQty     <- qty
                ))
            }
            recalculateReplenishment(itemID: itemID, quantity: qty)
            updateSeasonalFlag(itemID: itemID)
        } catch {
            print("[DatabaseManager] markPurchased failed for itemID \(itemID): \(error)")
        }
    }

    // Scales next-restock by quantity so bulk buys don't inflate the date
    // by a single cycle. Called immediately after the transaction above.
    private func recalculateReplenishment(itemID: Int64, quantity: Int) {
        guard let cycleDays = fetchCycleDays(for: itemID) else { return }
        let scaledDays  = cycleDays * quantity
        let nextRestock = Calendar.current.date(
            byAdding: .day, value: scaledDays, to: Date()
        )
        try? db.run(
            userItemsTable
                .filter(userItemsItemID == itemID)
                .update(userItemsNextRestockDate <- nextRestock)
        )
    }

    // P1-E seasonal detection (MVP-lite).
    // Reads all purchase dates for this item; if stddev of inter-purchase gaps
    // > 30 days AND ≥ 3 purchases exist, marks item as seasonal.
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

    // MARK: - ReplenishmentEngine helpers (Task #2)

    /// Fetches a single UserItem by its item_id.
    /// Used by ReplenishmentEngine to read cycle + seasonal data without
    /// loading the entire list. Returns nil if the item doesn't exist.
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

    /// Directly sets the next_restock_date for an item.
    /// Called by ReplenishmentEngine after quantity-scaling a bulk purchase.
    func setNextRestockDate(itemID: Int64, date: Date?) {
        try? db.run(
            userItemsTable
                .filter(userItemsItemID == itemID)
                .update(userItemsNextRestockDate <- date)
        )
    }

    // MARK: - P1-G: Race-condition-safe flyer sale upsert
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
        let fmt = ISO8601DateFormatter()
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

    /// Returns the median purchase cycle in days for an item.
    /// Kept private — external callers use fetchUserItem() to get effectiveCycleDays.
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

    // Migration helper — call inside runMigrations().
    func applyFlyerSalesUniqueIndex() {
        try? db.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_flyer_unique
            ON flyer_sales(item_id, store_id, sale_start_date)
        """)
    }

    // MARK: - Per-item alert check
    func hasAlertFiredForItem(itemID: Int64) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let count = (try? db.scalar(
            alertLogTable.filter(alertItemID == itemID && alertFiredAt >= startOfToday).count
        )) ?? 0
        return count > 0
    }
}
