// DatabaseManager+Purchases.swift
// Extension on DatabaseManager for purchase_history writes used by
// ReceiptImportService (date-aware variant of markPurchased).
//
// Fix (Part 4): recalculateReplenishment now uses the quantity-aware
// 2-arg signature from DatabaseManager+Fixes.swift.
// The old 1-arg version was removed in Part 3.

import Foundation
import SQLite

extension DatabaseManager {

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
            // Use the quantity-aware signature from +Fixes.
            recalculateReplenishment(itemID: itemID, quantity: qty)
        } catch {
            print("[DatabaseManager] markPurchasedOnDate failed for itemID \(itemID): \(error)")
        }
    }
}
