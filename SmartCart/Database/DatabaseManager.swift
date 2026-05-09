// DatabaseManager.swift — SmartCart/Database/DatabaseManager.swift
//
// SINGLE GATEWAY for all SQLite reads and writes.
// Views and ViewModels NEVER write raw SQL — all DB access goes through here.
//
// Fixes included:
//   P0-1: markPurchased() is now atomic — writes purchase_history internally.
//         HomeViewModel.confirmPurchase() no longer calls insertPurchase() separately.
//   P1-5: hasAlertFiredForItem(itemID:) added — per-item alert check, not global.
//   P1-8: insertFlyerSale() uses INSERT OR IGNORE against idx_flyer_unique.
//
// Usage:
//   DatabaseManager.shared.setup()   — call once in SmartCartApp.init()
//   DatabaseManager.shared.fetchUserItems()
//   DatabaseManager.shared.markPurchased(itemID:priceAtPurchase:)

import Foundation
import SQLite

final class DatabaseManager {

    // Shared singleton — use this everywhere.
    static let shared = DatabaseManager()
    private init() {}

    private var db: Connection!

    // MARK: - Table + column references (SQLite.swift Expression types)

    // stores
    private let storesTable         = Table("stores")
    private let storeID             = Expression<Int64>("id")
    private let storeName           = Expression<String>("name")
    private let storeFlippID        = Expression<String?>("flipp_id")
    private let storeIsSelected     = Expression<Int64>("is_selected")
    private let storeLastSyncedAt   = Expression<String?>("last_synced_at")

    // items
    private let itemsTable          = Table("items")
    private let itemID              = Expression<Int64>("id")
    private let itemNameNormalised  = Expression<String>("name_normalised")
    private let itemNameDisplay     = Expression<String>("name_display")
    private let itemCategory        = Expression<String?>("category")
    private let itemUnit            = Expression<String?>("unit")
    private let itemCreatedAt       = Expression<String>("created_at")

    // user_items
    private let userItemsTable              = Table("user_items")
    private let userItemsID                 = Expression<Int64>("id")
    private let userItemsItemID             = Expression<Int64>("item_id")
    private let userItemsLastPurchasedDate  = Expression<String?>("last_purchased_date")
    private let userItemsLastPurchasedPrice = Expression<Double?>("last_purchased_price")
    private let userItemsReplenishInferred  = Expression<Int64?>("replenishment_inferred")
    private let userItemsReplenishOverride  = Expression<Int64?>("replenishment_override")
    private let userItemsNextRestockDate    = Expression<String?>("next_restock_date")

    // purchase_history
    private let purchaseHistoryTable = Table("purchase_history")
    private let purchaseID           = Expression<Int64>("id")
    private let purchaseItemID       = Expression<Int64>("item_id")
    private let purchasedAt          = Expression<String>("purchased_at")
    private let purchasePrice        = Expression<Double?>("price")
    private let purchaseSource       = Expression<String>("source")
    private let purchaseStoreID      = Expression<Int64?>("store_id")

    // price_history
    private let priceHistoryTable = Table("price_history")
    private let priceHistID       = Expression<Int64>("id")
    private let priceHistItemID   = Expression<Int64>("item_id")
    private let priceHistStoreID  = Expression<Int64>("store_id")
    private let priceHistPrice    = Expression<Double>("price")
    private let priceHistObsAt    = Expression<String>("observed_at")
    private let priceHistSource   = Expression<String>("source")

    // flyer_sales
    private let flyerSalesTable  = Table("flyer_sales")
    private let flyerID          = Expression<Int64>("id")
    private let flyerItemID      = Expression<Int64>("item_id")
    private let flyerStoreID     = Expression<Int64>("store_id")
    private let flyerSalePrice   = Expression<Double>("sale_price")
    private let flyerStartDate   = Expression<String>("sale_start_date")
    private let flyerEndDate     = Expression<String?>("sale_end_date")
    private let flyerSource      = Expression<String>("source")
    private let flyerFetchedAt   = Expression<String>("fetched_at")

    // alert_log
    private let alertLogTable      = Table("alert_log")
    private let alertLogID         = Expression<Int64>("id")
    private let alertItemID        = Expression<Int64>("item_id")
    private let alertType          = Expression<String>("alert_type")
    private let alertTriggerPrice  = Expression<Double>("trigger_price")
    private let alertFiredAt       = Expression<String>("fired_at")
    private let alertNotifID       = Expression<String?>("notification_id")

    // user_settings
    private let settingsTable = Table("user_settings")
    private let settingKey    = Expression<String>("key")
    private let settingValue  = Expression<String>("value")

    // MARK: - Setup

    // Call once at app launch in SmartCartApp.init().
    // Creates all tables and seeds default settings if missing.
    func setup() {
        do {
            let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            db = try Connection("\(path)/smartcart.sqlite3")
            db.busyTimeout = 5
            try db.execute("PRAGMA foreign_keys = ON")
            try runMigrations()
            seedDefaultSettings()
        } catch {
            fatalError("[DatabaseManager] setup() failed: \(error)")
        }
    }

    // Creates all tables in Schema.allCreateStatements order.
    // Safe to call on every launch — all statements use IF NOT EXISTS.
    private func runMigrations() throws {
        for statement in Schema.allCreateStatements {
            try db.execute(statement)
        }
    }

    // Inserts default settings rows only if the key does not already exist.
    private func seedDefaultSettings() {
        for setting in Schema.defaultSettings {
            let insert = settingsTable.insert(or: .ignore,
                settingKey   <- setting.key,
                settingValue <- setting.value
            )
            try? db.run(insert)
        }
    }

    // MARK: - Settings

    func getSetting(key: String) -> String? {
        let row = settingsTable.filter(settingKey == key)
        return (try? db.pluck(row))?[settingValue]
    }

    func setSetting(key: String, value: String) {
        let upsert = settingsTable.insert(or: .replace,
            settingKey   <- key,
            settingValue <- value
        )
        try? db.run(upsert)
    }

    func deleteSetting(key: String) {
        let row = settingsTable.filter(settingKey == key)
        try? db.run(row.delete())
    }

    // MARK: - Stores

    // Inserts a new store or returns the existing store’s id if name already exists.
    @discardableResult
    func upsertStore(name: String) -> Int64 {
        if let existing = try? db.pluck(storesTable.filter(storeName == name)) {
            return existing[storeID]
        }
        let insert = storesTable.insert(
            storeName       <- name,
            storeIsSelected <- 1
        )
        return (try? db.run(insert)) ?? -1
    }

    // Returns all stores where is_selected = 1.
    func fetchSelectedStores() -> [Store] {
        let query = storesTable.filter(storeIsSelected == 1)
        return (try? db.prepare(query).map { row in
            Store(
                id: row[storeID],
                name: row[storeName],
                flippID: row[storeFlippID],
                isSelected: row[storeIsSelected] == 1,
                lastSyncedAt: row[storeLastSyncedAt].flatMap { DateHelper.date(from: $0) }
            )
        }) ?? []
    }

    // MARK: - Items

    // Inserts item if nameNormalised is new; returns existing id if already present.
    // Also inserts a user_items row if one does not exist for this item.
    @discardableResult
    func upsertItem(nameDisplay: String, nameNormalised: String) -> Int64 {
        if let existing = try? db.pluck(itemsTable.filter(itemNameNormalised == nameNormalised)) {
            return existing[itemID]
        }
        let insert = itemsTable.insert(
            itemNameNormalised <- nameNormalised,
            itemNameDisplay    <- nameDisplay,
            itemCreatedAt      <- DateHelper.nowString()
        )
        guard let newID = try? db.run(insert) else { return -1 }
        let userInsert = userItemsTable.insert(
            userItemsItemID <- newID
        )
        try? db.run(userInsert)
        return newID
    }

    // MARK: - User Items

    // Row returned from a joined query across user_items + items.
    struct UserItemRow {
        let itemID: Int64
        let nameDisplay: String
        let lastPurchasedDate: String?
        let lastPurchasedPrice: Double?
        let replenishmentInferred: Int64?
        let replenishmentOverride: Int64?
        let nextRestockDate: String?
    }

    // Fetches all user_items joined with items, ordered by next_restock_date ASC.
    func fetchUserItems() -> [UserItemRow] {
        let query = userItemsTable
            .join(itemsTable, on: userItemsItemID == itemID)
            .order(userItemsNextRestockDate.asc)
        return (try? db.prepare(query).map { row in
            UserItemRow(
                itemID:                row[userItemsItemID],
                nameDisplay:           row[itemNameDisplay],
                lastPurchasedDate:     row[userItemsLastPurchasedDate],
                lastPurchasedPrice:    row[userItemsLastPurchasedPrice],
                replenishmentInferred: row[userItemsReplenishInferred],
                replenishmentOverride: row[userItemsReplenishOverride],
                nextRestockDate:       row[userItemsNextRestockDate]
            )
        }) ?? []
    }

    // MARK: - Purchase History

    // P0-1 Fix: markPurchased() is now atomic.
    // Writes purchase_history AND updates user_items in a single transaction.
    // Call this exclusively — never call insertPurchase() separately.
    func markPurchased(itemID: Int64, priceAtPurchase: Double?) {
        let today = DateHelper.nowString()
        do {
            try db.transaction {
                let userItem = userItemsTable.filter(userItemsItemID == itemID)
                try db.run(userItem.update(
                    userItemsLastPurchasedDate  <- today,
                    userItemsLastPurchasedPrice <- priceAtPurchase,
                    userItemsNextRestockDate    <- nil
                ))
                try db.run(purchaseHistoryTable.insert(
                    purchaseItemID <- itemID,
                    purchasedAt    <- today,
                    purchasePrice  <- priceAtPurchase,
                    purchaseSource <- "receipt"
                ))
            }
            recalculateReplenishment(itemID: itemID)
        } catch {
            print("[DatabaseManager] markPurchased failed for itemID \(itemID): \(error)")
        }
    }

    // Recalculates the median purchase interval and updates next_restock_date.
    // Called automatically by markPurchased().
    private func recalculateReplenishment(itemID: Int64) {
        let history = purchaseHistoryTable
            .filter(purchaseItemID == itemID)
            .order(purchasedAt.asc)
        guard let rows = try? db.prepare(history).map({ $0[purchasedAt] }),
              rows.count >= 2 else { return }

        let dates = rows.compactMap { DateHelper.date(from: $0) }
        var intervals: [Int] = []
        for i in 1..<dates.count {
            let days = Calendar.current.dateComponents([.day], from: dates[i-1], to: dates[i]).day ?? 0
            if days > 0 { intervals.append(days) }
        }
        guard !intervals.isEmpty else { return }

        // TODO: use true median for even-count arrays (P2-1)
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]

        let nextRestock = Calendar.current.date(byAdding: .day, value: median, to: dates.last!)!
        let nextRestockStr = DateHelper.string(from: nextRestock)

        let userItem = userItemsTable.filter(userItemsItemID == itemID)
        try? db.run(userItem.update(
            userItemsReplenishInferred <- Int64(median),
            userItemsNextRestockDate   <- nextRestockStr
        ))
    }

    // MARK: - Price History

    func insertPriceHistory(itemID: Int64, storeID: Int64, price: Double, source: String = "flipp") {
        let insert = priceHistoryTable.insert(
            priceHistItemID  <- itemID,
            priceHistStoreID <- storeID,
            priceHistPrice   <- price,
            priceHistObsAt   <- DateHelper.nowString(),
            priceHistSource  <- source
        )
        try? db.run(insert)
    }

    // Returns the 90-day rolling average price for an item across all selected stores.
    func rollingAverage90(itemID: Int64) -> Double? {
        let cutoff = DateHelper.string(from: Calendar.current.date(byAdding: .day, value: -90, to: Date())!)
        let query = priceHistoryTable
            .filter(priceHistItemID == itemID && priceHistObsAt >= cutoff)
            .select(priceHistPrice.average)
        return (try? db.scalar(query)) ?? nil
    }

    // Returns the all-time lowest recorded regular price for an item.
    func historicalLow(itemID: Int64) -> Double? {
        let query = priceHistoryTable
            .filter(priceHistItemID == itemID)
            .select(priceHistPrice.min)
        return (try? db.scalar(query)) ?? nil
    }

    // Returns the current lowest price from price_history (most recent observation).
    func currentLowestPrice(for itemID: Int64) -> Double? {
        let query = priceHistoryTable
            .filter(priceHistItemID == itemID)
            .order(priceHistObsAt.desc)
            .limit(1)
            .select(priceHistPrice)
        return (try? db.pluck(query))?[priceHistPrice]
    }

    // MARK: - Flyer Sales

    // P1-8 Fix: INSERT OR IGNORE against idx_flyer_unique prevents duplicate rows.
    func insertFlyerSale(itemID: Int64, storeID: Int64, salePrice: Double,
                         startDate: String, endDate: String?, source: String = "flipp") {
        let insert = flyerSalesTable.insert(or: .ignore,
            flyerItemID    <- itemID,
            flyerStoreID   <- storeID,
            flyerSalePrice <- salePrice,
            flyerStartDate <- startDate,
            flyerEndDate   <- endDate,
            flyerSource    <- source,
            flyerFetchedAt <- DateHelper.nowString()
        )
        try? db.run(insert)
        // Update fetched_at on the existing row so we know it was seen today
        let existing = flyerSalesTable.filter(
            flyerItemID == itemID && flyerStoreID == storeID &&
            flyerStartDate == startDate && flyerSalePrice == salePrice
        )
        try? db.run(existing.update(flyerFetchedAt <- DateHelper.nowString()))
    }

    // Returns all active flyer sales for a given item (today is within [start, end]).
    func fetchActiveSales(itemID: Int64) -> [FlyerSale] {
        let today = DateHelper.todayString()
        let query = flyerSalesTable.filter(
            flyerItemID == itemID &&
            flyerStartDate <= today &&
            (flyerEndDate == nil || flyerEndDate >= today)
        )
        return (try? db.prepare(query).map { row in
            FlyerSale(
                id:        row[flyerID],
                itemID:    row[flyerItemID],
                storeID:   row[flyerStoreID],
                salePrice: row[flyerSalePrice],
                validFrom: DateHelper.date(from: row[flyerStartDate]) ?? Date(),
                validTo:   row[flyerEndDate].flatMap { DateHelper.date(from: $0) },
                source:    row[flyerSource],
                fetchedAt: DateHelper.date(from: row[flyerFetchedAt]) ?? Date()
            )
        }) ?? []
    }

    // MARK: - Alert Log

    // Counts alerts fired today across ALL items (used for daily cap check).
    func alertsFiredToday() -> Int {
        let startOfToday = DateHelper.todayString()
        return (try? db.scalar(alertLogTable.filter(alertFiredAt >= startOfToday).count)) ?? 0
    }

    // P1-5 Fix: Per-item alert check. Returns true if any alert fired for this item today.
    func hasAlertFiredForItem(itemID: Int64) -> Bool {
        let startOfToday = DateHelper.todayString()
        let count = (try? db.scalar(
            alertLogTable.filter(alertItemID == itemID && alertFiredAt >= startOfToday).count
        )) ?? 0
        return count > 0
    }

    // Writes an alert_log row. Call this BEFORE scheduling the UNNotification.
    func logAlert(itemID: Int64, alertType: String, triggerPrice: Double, notificationID: String?) {
        let insert = alertLogTable.insert(
            alertItemID      <- itemID,
            alertType        <- alertType,
            alertTriggerPrice <- triggerPrice,
            alertFiredAt     <- DateHelper.nowString(),
            alertNotifID     <- notificationID
        )
        try? db.run(insert)
    }
}
