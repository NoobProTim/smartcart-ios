// DatabaseManager+Purchases.swift
// SmartCart — Database/DatabaseManager+Purchases.swift
//
// Extension on DatabaseManager for purchase_history writes and reads.
//
// markPurchasedOnDate() — used by ReceiptImportService (date-aware purchase write).
// fetchPurchaseDates()  — used by ReplenishmentEngine.inferCycleDays() to get
//                         raw purchase dates for true median calculation.
//                         This method is data-only: it returns sorted Date values,
//                         no gap math, no inference logic.

import Foundation
import SQLite

extension DatabaseManager {

    // MARK: - markPurchasedOnDate(itemID:priceAtPurchase:storeID:date:source:quantity:)
    // Date-aware version of markPurchased() used by ReceiptImportService.
    // Writes purchase_history with the receipt date instead of today,
    // and updates user_items last_purchased fields atomically.
    // quantity defaults to 1 for receipt imports (single-unit assumption).
    func markPurchasedOnDate(
        itemID: Int64,
        priceAtPurchase: Double?,
        storeID: Int64?,
        date: Date,
        source: String,
        quantity: Int = 1
    ) {
        let qty = max(1, quantity)
        do {
            try db.transaction {
                let userItem = userItemsTable.filter(userItemsItemID == itemID)
                try db.run(userItem.update(
                    userItemsLastPurchasedDate  <- date,
                    userItemsLastPurchasedPrice <- priceAtPurchase,
                    userItemsLastStoreID        <- storeID,
                    userItemsNextRestockDate    <- nil
                ))
                try db.run(purchaseHistoryTable.insert(
                    purchaseItemID  <- itemID,
                    purchaseStoreID <- storeID,
                    purchasedAt     <- date,
                    purchasePrice   <- priceAtPurchase,
                    purchaseSource  <- source,
                    purchaseQty     <- Int64(qty)
                ))
            }
            // Delegates to ReplenishmentEngine via recalculateReplenishment shim in +Fixes.
            recalculateReplenishment(itemID: itemID, quantity: qty)
        } catch {
            print("[DatabaseManager] markPurchasedOnDate failed for itemID \(itemID): \(error)")
        }
    }

    // MARK: - fetchPurchaseDates(itemID:)
    // Returns all purchase dates for an item, sorted oldest-first.
    // DATA ONLY — no gap calculation, no median, no inference logic here.
    // ReplenishmentEngine.inferCycleDays() calls this and does all the math itself.
    // Returns an empty array if no purchases exist.
    func fetchPurchaseDates(itemID: Int64) -> [Date] {
        let rows = (try? db.prepare(
            purchaseHistoryTable
                .filter(purchaseItemID == itemID)
                .order(purchasedAt.asc)
                .select(purchasedAt)
        )) ?? AnySequence([])
        return rows.compactMap { $0[purchasedAt] as Date? }
    }
}
