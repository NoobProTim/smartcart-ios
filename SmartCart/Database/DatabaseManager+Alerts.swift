// DatabaseManager+Alerts.swift
// Extension on DatabaseManager for alert_log helpers used by AlertEngine.

import Foundation
import SQLite

extension DatabaseManager {

    // Returns true if a historical_low alert for this item already fired today.
    func hasAlertFiredForItemType(itemID: Int64, type: AlertType) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let count = (try? db.scalar(
            alertLogTable.filter(
                alertItemID == itemID &&
                alertType   == type.rawValue &&
                alertFiredAt >= startOfToday
            ).count
        )) ?? 0
        return count > 0
    }

    // Returns true if any alert (any type) for a specific flyer sale event
    // has already been logged. Prevents re-firing B or C for the same sale.
    func hasAlertFiredForSaleEvent(
        itemID: Int64,
        saleEventID: Int64,
        type: AlertType? = nil
    ) -> Bool {
        var query = alertLogTable.filter(
            alertItemID     == itemID &&
            alertSaleEventID == saleEventID
        )
        if let t = type {
            query = query.filter(alertType == t.rawValue)
        }
        return (try? db.scalar(query.count)) ?? 0 > 0
    }

    // Returns flyer_sales rows for an item whose sale_end_date falls
    // exactly N days from today. Used for Type C (Expiry Reminder).
    func fetchSalesExpiring(for itemID: Int64, inDays days: Int) -> [FlyerSale] {
        guard let targetDate = Calendar.current.date(
            byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date())
        ) else { return [] }
        let next = Calendar.current.date(byAdding: .day, value: 1, to: targetDate)!
        let rows = (try? db.prepare(
            flyerSalesTable.filter(
                flyerItemID  == itemID &&
                flyerEndDate >= targetDate &&
                flyerEndDate <  next
            )
        )) ?? AnySequence([])
        return rows.map { row in
            FlyerSale(
                id:          row[flyerID],
                itemID:      row[flyerItemID],
                storeID:     row[flyerStoreID],
                salePrice:   row[flyerSalePrice],
                regularPrice: row[flyerRegularPrice],
                validFrom:   row[flyerStartDate],
                validTo:     row[flyerEndDate],
                source:      row[flyerSource],
                fetchedAt:   row[flyerFetchedAt]
            )
        }
    }

    // Returns true if the user purchased the item during the sale window.
    // Used by AlertEngine Step 4 to suppress Type C if already bought.
    func purchasedDuringSale(itemID: Int64, sale: FlyerSale) -> Bool {
        let end = sale.validTo ?? Date()
        let count = (try? db.scalar(
            purchaseHistoryTable.filter(
                purchaseItemID == itemID &&
                purchasedAt >= sale.validFrom &&
                purchasedAt <= end
            ).count
        )) ?? 0
        return count > 0
    }

    // Returns the store_id most recently used to purchase an item.
    // Used by AlertEngine when building an AlertCandidate without a sale event.
    func primaryStoreID(for itemID: Int64) -> Int64? {
        let row = try? db.pluck(
            userItemsTable
                .filter(userItemsItemID == itemID)
                .select(userItemsLastStoreID)
        )
        return row.flatMap { $0[userItemsLastStoreID] }
    }

    // Returns the display name for a store_id.
    func storeName(for storeID: Int64) -> String? {
        let row = try? db.pluck(storesTable.filter(self.storeID == storeID).select(storeName))
        return row?[storeName]
    }
}
