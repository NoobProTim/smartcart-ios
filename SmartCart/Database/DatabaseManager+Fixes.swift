// DatabaseManager+Fixes.swift
// SmartCart — Database/DatabaseManager+Fixes.swift
//
// Retroactive fixes from PRISM Task #1-R1 review.
// These replace or extend methods in DatabaseManager.swift.
//
// P0-1: markPurchased() is now atomic — writes purchase_history internally.
//        HomeViewModel.confirmPurchase() must NOT call insertPurchase() separately.
// P1-5: hasAlertFiredForItem() replaces the global alertsFiredToday() check.
//        hasActiveAlert on UserItem is now per-item, not a global badge.
// P1-8: insertFlyerSale() uses INSERT OR IGNORE.
//        Unique index on (item_id, store_id, sale_start_date, sale_price)
//        prevents duplicate rows on every daily sync.

import Foundation

extension DatabaseManager {

    // MARK: — P0-1: Atomic purchase write
    // Writes both user_items UPDATE and purchase_history INSERT in one transaction.
    // Call this from all purchase confirmation paths — never call insertPurchase() directly.
    func markPurchased(itemID: Int64, priceAtPurchase: Double?) {
        let today = Date()
        do {
            try db.transaction {
                let userItem = userItems.filter(userItemsItemID == itemID)
                try db.run(userItem.update(
                    userItemsLastPurchasedDate <- today,
                    userItemsNextRestockDate   <- nil
                ))
                try db.run(purchaseHistoryTable.insert(
                    purchaseItemID <- itemID,
                    purchasedAt    <- today,
                    purchasePrice  <- priceAtPurchase
                ))
            }
            recalculateReplenishment(itemID: itemID)
        } catch {
            print("[DatabaseManager] markPurchased failed for itemID \(itemID): \(error)")
        }
    }

    // MARK: — P1-5: Per-item alert check
    // Returns true if an alert has already fired for this specific item today.
    // Used to set hasActiveAlert on each UserItem row individually.
    func hasAlertFiredForItem(itemID: Int64) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let count = (try? db.scalar(
            alertLogTable.filter(alertItemID == itemID && alertFiredAt >= startOfToday).count
        )) ?? 0
        return count > 0
    }

    // MARK: — P1-8: Duplicate-safe flyer sale insert
    // INSERT OR IGNORE prevents duplicate rows accumulating on every daily Flipp sync.
    // The unique index (idx_flyer_unique) must exist — created in runMigrations().
    func insertFlyerSale(itemID: Int64, storeID: Int64, salePrice: Double,
                         startDate: Date, endDate: Date?, source: String) {
        let insert = flyerSalesTable.insert(or: .ignore,
            flyerItemID    <- itemID,
            flyerStoreID   <- storeID,
            flyerSalePrice <- salePrice,
            flyerStartDate <- startDate,
            flyerEndDate   <- endDate,
            flyerSource    <- source,
            flyerFetchedAt <- Date()
        )
        try? db.run(insert)
        // Refresh fetchedAt on the existing row so staleness checks stay accurate.
        let existing = flyerSalesTable.filter(
            flyerItemID == itemID && flyerStoreID == storeID &&
            flyerStartDate == startDate && flyerSalePrice == salePrice
        )
        try? db.run(existing.update(flyerFetchedAt <- Date()))
    }

    // MARK: — P1-8: Migration helper
    // Call this inside runMigrations() to create the unique index.
    func applyFlyerSalesUniqueIndex() {
        try? db.execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_flyer_unique
            ON flyer_sales(item_id, store_id, sale_start_date, sale_price)
        """)
    }
}
