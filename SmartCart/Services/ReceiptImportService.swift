// ReceiptImportService.swift — SmartCart/Services/ReceiptImportService.swift
//
// Takes a ReceiptScanResult and persists confirmed items to the database.
// Called after the user reviews and confirms the scanned items on the
// ReceiptReviewView.

import Foundation

final class ReceiptImportService {

    static let shared = ReceiptImportService()
    private let db = DatabaseManager.shared
    private init() {}

    // Persists a confirmed set of scanned items to the database.
    // Each item is upserted into items + user_items, then a purchase_history
    // row is written and replenishment is recalculated.
    //
    // Parameters:
    //   items       — the ScannedLineItems the user confirmed (may be a subset of scan)
    //   storeID     — resolved store_id (0 if store not recognised)
    //   receiptDate — date from receipt, or today if nil
    func importConfirmedItems(
        items: [ScannedLineItem],
        storeID: Int64,
        receiptDate: Date?
    ) {
        let date = receiptDate ?? Date()
        for scanned in items {
            // 1. Upsert master item catalogue.
            let iid = db.upsertItem(
                nameNormalised: scanned.nameNormalised,
                nameDisplay:    scanned.nameRaw
            )
            // 2. Ensure user_items row exists.
            db.upsertUserItem(itemIDValue: iid)

            // 3. Write purchase history + update user_items atomically (Fix P0-1).
            //    markPurchased() handles the transaction; pass scanned price.
            db.markPurchasedOnDate(
                itemID:          iid,
                priceAtPurchase: scanned.price,
                storeID:         storeID > 0 ? storeID : nil,
                date:            date,
                source:          "receipt"
            )
        }
    }

    // Attempts to match a store name string (from OCR) to a stores row.
    // Returns the store_id if found, nil if not recognised.
    func resolveStore(nameRaw: String?) -> Int64? {
        guard let raw = nameRaw else { return nil }
        let lower = raw.lowercased()
        // Common Canadian grocery chains — extend as needed.
        let knownChains: [(keywords: [String], canonicalName: String)] = [
            (["loblaws", "loblaw"],                        "Loblaws"),
            (["no frills", "nofrills"],                    "No Frills"),
            (["real canadian", "superstore"],              "Real Canadian Superstore"),
            (["metro"],                                    "Metro"),
            (["sobeys"],                                   "Sobeys"),
            (["freshco"],                                  "FreshCo"),
            (["food basics"],                              "Food Basics"),
            (["walmart"],                                  "Walmart"),
            (["costco"],                                   "Costco"),
            (["iga"],                                      "IGA"),
            (["t&t", "t & t"],                             "T&T Supermarket"),
            (["farm boy"],                                 "Farm Boy"),
            (["longos", "longo's"],                        "Longo's"),
        ]
        for chain in knownChains {
            if chain.keywords.contains(where: { lower.contains($0) }) {
                return db.upsertStore(name: chain.canonicalName)
            }
        }
        return nil
    }
}
