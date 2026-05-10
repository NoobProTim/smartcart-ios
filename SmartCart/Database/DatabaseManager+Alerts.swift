// DatabaseManager+Alerts.swift
import Foundation
import SQLite

extension DatabaseManager {

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

    func hasAlertFiredForSaleEvent(
        itemID: Int64,
        saleEventID: Int64,
        type: AlertType? = nil
    ) -> Bool {
        var query = alertLogTable.filter(
            alertItemID      == itemID &&
            alertSaleEventID == saleEventID
        )
        if let t = type { query = query.filter(alertType == t.rawValue) }
        return (try? db.scalar(query.count)) ?? 0 > 0
    }

    // P1-A: Returns the number of alerts fired since the most recent Monday 00:00 local time.
    func alertsFiredThisWeek() -> Int {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        guard let startOfWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return 0
        }
        return (try? db.scalar(
            alertLogTable.filter(alertFiredAt >= startOfWeek).count
        )) ?? 0
    }

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
                id:           row[flyerID],
                itemID:       row[flyerItemID],
                storeID:      row[flyerStoreID],
                salePrice:    row[flyerSalePrice],
                regularPrice: row[flyerRegularPrice],
                validFrom:    row[flyerStartDate],
                validTo:      row[flyerEndDate],
                source:       row[flyerSource],
                fetchedAt:    row[flyerFetchedAt]
            )
        }
    }

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

    func primaryStoreID(for itemID: Int64) -> Int64? {
        let row = try? db.pluck(
            userItemsTable
                .filter(userItemsItemID == itemID)
                .select(userItemsLastStoreID)
        )
        return row.flatMap { $0[userItemsLastStoreID] }
    }

    // Fix: renamed from storeName(for storeID:) to eliminate two naming collisions:
    //   1. Method name `storeName` shadowed the module-level Expression<String> `storeName`
    //      making `row?[storeName]` potentially resolve to the recursive function instead of the column.
    //   2. Parameter `storeID` shadowed the module-level Expression<Int64> `storeID`
    //      making `storesTable.filter(storeID == storeIDParam)` possibly compile as Bool == Bool
    //      rather than a SQLite Expression predicate.
    // AlertEngine.swift updated to call db.fetchStoreName(for:) instead.
    func fetchStoreName(for storeIDParam: Int64) -> String? {
        // Use local aliases to guarantee the compiler binds to the module-level
        // Expression constants, not the parameter or this method.
        let colID:   Expression<Int64>  = storeID
        let colName: Expression<String> = storeName
        let row = try? db.pluck(storesTable.filter(colID == storeIDParam).select(colName))
        return row?[colName]
    }
}
