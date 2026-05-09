// DatabaseManager+Purchases.swift
// Extension on DatabaseManager for purchase_history writes used by
// ReceiptImportService (date-aware variant of markPurchased).

import Foundation
import SQLite

extension DatabaseManager {

    // Date-aware version of markPurchased() used by ReceiptImportService.
    // Writes purchase_history with the receipt date instead of today,
    // and updates user_items last_purchased fields atomically.
    // Fix P0-1: all writes are inside a single db.transaction {}.
    func markPurchasedOnDate(
        itemID: Int64,
        priceAtPurchase: Double?,
        storeID: Int64?,
        date: Date,
        source: String
    ) {
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
                    purchaseSource  <- source
                ))
            }
            recalculateReplenishment(itemID: itemID)
        } catch {
            print("[DatabaseManager] markPurchasedOnDate failed for itemID \(itemID): \(error)")
        }
    }
}
