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

    // MARK: - fetchAlertLogRow(alertLogID:)
    // Fetches a single alert_log row by its primary key.
    // Used by AlertDetailView to display the price and type of a fired alert.
    func fetchAlertLogRow(alertLogID: Int64) -> AlertLog? {
        guard let row = try? db.pluck(alertLogTable.filter(alertID == alertLogID)) else { return nil }
        let sid = row[alertStoreID]
        return AlertLog(
            id:             row[alertID],
            itemID:         row[alertItemID],
            storeID:        sid,
            alertType:      row[alertType],
            triggerPrice:   row[alertPrice],
            firedAt:        row[alertFiredAt],
            notificationID: row[alertNotifID],
            saleEventID:    row[alertSaleEventID]
        )
    }

    // MARK: - fetchSaleEndDate(saleEventID:)
    // Returns the sale_end_date for a flyer_sales row as a Date.
    // Used by AlertDetailView to show "Sale ends May 17".
    func fetchSaleEndDate(saleEventID: Int64) -> Date? {
        guard let row = try? db.pluck(flyerSalesTable.filter(flyerID == saleEventID)) else { return nil }
        return row[flyerEndDate]
    }

    // MARK: - insertAlertLog(itemID:alertType:triggerPrice:notificationID:)
    // Simplified log writer used by AlertEngine.evaluate().
    // AlertEngine doesn't track storeID at the candidate level, so storeID defaults to 0.
    func insertAlertLog(itemID: Int64, alertType alertTypeValue: String,
                        triggerPrice: Double, notificationID: String?) {
        _ = try? db.run(alertLogTable.insert(
            alertItemID      <- itemID,
            alertStoreID     <- Int64(0),
            alertType        <- alertTypeValue,
            alertPrice       <- triggerPrice,
            alertFiredAt     <- Date(),
            alertSaleEventID <- Optional<Int64>.none,
            alertNotifID     <- notificationID
        ))
    }

    // MARK: - storeNameForCurrentLowestPrice(itemID:)
    // Returns the name of the store with the lowest price_history price
    // for this item in the last 7 days. Used by AlertEngine Type A evaluation.
    func storeNameForCurrentLowestPrice(itemID: Int64) -> String? {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        guard let row = try? db.pluck(
            priceHistoryTable
                .filter(priceHistItemID == itemID && priceHistDate >= sevenDaysAgo)
                .order(priceHistPrice.asc)
                .select(priceHistStoreID)
        ) else { return nil }
        return fetchStoreName(for: row[priceHistStoreID])
    }

    // MARK: - activeSaleForItem(itemID:)
    // Returns the first currently active flyer sale for an item, or nil.
    // Used by AlertEngine Type B and C evaluation.
    func activeSaleForItem(itemID: Int64) -> FlyerSale? {
        return fetchActiveSales(for: itemID).first
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
        let colID:   SQLite.Expression<Int64>  = storeID
        let colName: SQLite.Expression<String> = storeName
        let row = try? db.pluck(storesTable.filter(colID == storeIDParam).select(colName))
        return row?[colName]
    }
}
