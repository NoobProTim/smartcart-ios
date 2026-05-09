// DatabaseManager.swift — SmartCart/Database/DatabaseManager.swift
//
// The single point of contact between the app and the local SQLite database.
// All reads and writes go through this class — no raw SQLite anywhere else.
//
// Uses SQLite.swift (stephencelis/SQLite.swift 0.15.x).
// Access via DatabaseManager.shared (singleton).

import Foundation
import SQLite

final class DatabaseManager {

    // Shared instance — the whole app uses one DatabaseManager.
    static let shared = DatabaseManager()

    // The live SQLite connection. Opened once on init.
    private var db: Connection!

    private init() {
        do {
            // Store the database file in the app's Documents directory so it
            // persists across launches and is included in iCloud backups.
            let docURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = docURL.appendingPathComponent("smartcart.sqlite3")
            db = try Connection(dbURL.path)
            // Enable WAL mode: faster writes, safer concurrent reads.
            try db.execute("PRAGMA journal_mode = WAL")
            // Enforce foreign key constraints.
            try db.execute("PRAGMA foreign_keys = ON")
            runMigrations()
        } catch {
            fatalError("[DatabaseManager] Failed to open SQLite: \(error)")
        }
    }

    // MARK: - Migrations

    // Creates all tables and indexes if they don't exist.
    // Safe to call on every launch — uses IF NOT EXISTS everywhere.
    func runMigrations() {
        do {
            // stores
            try db.run(storesTable.create(ifNotExists: true) { t in
                t.column(storeID, primaryKey: .autoincrement)
                t.column(storeName)
                t.column(storeLogoURL)
                t.column(storeFlippID)
                t.column(storeIsSelected, defaultValue: 0)
                t.column(storeLastSynced)
            })

            // items
            try db.run(itemsTable.create(ifNotExists: true) { t in
                t.column(itemID, primaryKey: .autoincrement)
                t.column(itemNameNormalised, unique: true)
                t.column(itemNameDisplay)
                t.column(itemCategory)
                t.column(itemUnit)
                t.column(itemCreatedAt)
            })
            try db.execute("CREATE INDEX IF NOT EXISTS idx_items_name ON items(name_normalised)")

            // user_items
            try db.run(userItemsTable.create(ifNotExists: true) { t in
                t.column(userItemID, primaryKey: .autoincrement)
                t.column(userItemsItemID, references: itemsTable, itemID)
                t.column(userItemsAddedDate)
                t.column(userItemsLastPurchasedDate)
                t.column(userItemsLastPurchasedPrice)
                t.column(userItemsLastStoreID)
                t.column(userItemsReplenishInferred)
                t.column(userItemsReplenishOverride)
                t.column(userItemsNextRestockDate)
                t.column(userItemsIsActive, defaultValue: 1)
            })
            try db.execute("CREATE INDEX IF NOT EXISTS idx_user_items_item ON user_items(item_id)")

            // purchase_history
            try db.run(purchaseHistoryTable.create(ifNotExists: true) { t in
                t.column(purchaseID, primaryKey: .autoincrement)
                t.column(purchaseItemID, references: itemsTable, itemID)
                t.column(purchaseStoreID)
                t.column(purchasePrice)
                t.column(purchasedAt)
                t.column(purchaseSource)
            })
            try db.execute("CREATE INDEX IF NOT EXISTS idx_purchase_item ON purchase_history(item_id, purchased_at)")

            // price_history
            try db.run(priceHistoryTable.create(ifNotExists: true) { t in
                t.column(priceHistID, primaryKey: .autoincrement)
                t.column(priceHistItemID, references: itemsTable, itemID)
                t.column(priceHistStoreID, references: storesTable, storeID)
                t.column(priceHistPrice)
                t.column(priceHistDate)
                t.column(priceHistSource)
            })
            try db.execute("CREATE INDEX IF NOT EXISTS idx_price_item_store ON price_history(item_id, store_id, observed_at)")

            // flyer_sales
            try db.run(flyerSalesTable.create(ifNotExists: true) { t in
                t.column(flyerID, primaryKey: .autoincrement)
                t.column(flyerItemID, references: itemsTable, itemID)
                t.column(flyerStoreID, references: storesTable, storeID)
                t.column(flyerSalePrice)
                t.column(flyerRegularPrice)
                t.column(flyerStartDate)
                t.column(flyerEndDate)
                t.column(flyerSource)
                t.column(flyerFetchedAt)
            })
            try db.execute("CREATE INDEX IF NOT EXISTS idx_flyer_item_store ON flyer_sales(item_id, store_id, sale_start_date)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_flyer_end_date ON flyer_sales(sale_end_date)")
            // Fix P1-8: unique index prevents duplicate rows on every daily sync.
            try db.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS idx_flyer_unique
                ON flyer_sales(item_id, store_id, sale_start_date, sale_price)
            """)

            // alert_log
            try db.run(alertLogTable.create(ifNotExists: true) { t in
                t.column(alertID, primaryKey: .autoincrement)
                t.column(alertItemID, references: itemsTable, itemID)
                t.column(alertStoreID, references: storesTable, storeID)
                t.column(alertType)
                t.column(alertPrice)
                t.column(alertFiredAt)
                t.column(alertSaleEventID)
                t.column(alertNotifID)
            })
            try db.execute("CREATE INDEX IF NOT EXISTS idx_alert_item_type ON alert_log(item_id, alert_type, fired_at)")
            try db.execute("CREATE INDEX IF NOT EXISTS idx_alert_sale_event ON alert_log(sale_event_id)")

            // user_stores
            try db.run(userStoresTable.create(ifNotExists: true) { t in
                t.column(Expression<Int64>("store_id"), primaryKey: true)
                t.foreignKey(Expression<Int64>("store_id"), references: storesTable, storeID)
                t.column(Expression<Int64>("selected"), defaultValue: 1)
            })

            // user_settings
            try db.run(userSettingsTable.create(ifNotExists: true) { t in
                t.column(settingKey, primaryKey: true)
                t.column(settingValue)
            })

            seedDefaultSettings()

        } catch {
            print("[DatabaseManager] Migration error: \(error)")
        }
    }

    // Inserts default user_settings rows if they don't already exist.
    private func seedDefaultSettings() {
        for (key, value) in defaultSettings {
            let row = userSettingsTable.filter(settingKey == key)
            if (try? db.scalar(row.count)) == 0 {
                try? db.run(userSettingsTable.insert(settingKey <- key, settingValue <- value))
            }
        }
    }

    // MARK: - Settings helpers

    // Reads a value from user_settings by key. Returns nil if the key doesn't exist.
    func getSetting(key: String) -> String? {
        let row = userSettingsTable.filter(settingKey == key)
        return try? db.pluck(row).flatMap { $0[settingValue] }
    }

    // Writes or replaces a value in user_settings.
    func setSetting(key: String, value: String?) {
        try? db.run(userSettingsTable.insert(or: .replace,
            settingKey <- key, settingValue <- value))
    }

    // Deletes a key from user_settings entirely.
    func deleteSetting(key: String) {
        try? db.run(userSettingsTable.filter(settingKey == key).delete())
    }

    // MARK: - Store helpers

    // Inserts a store by name if it doesn't already exist, then returns its ID.
    // Safe to call multiple times with the same name.
    @discardableResult
    func upsertStore(name: String) -> Int64 {
        if let existing = try? db.pluck(storesTable.filter(storeName == name)) {
            return existing[storeID]
        }
        let id = try? db.run(storesTable.insert(
            storeName <- name,
            storeIsSelected <- 1
        ))
        return id ?? 0
    }

    // Returns all stores that the user has selected (is_selected = 1).
    func fetchSelectedStores() -> [Store] {
        let rows = (try? db.prepare(storesTable.filter(storeIsSelected == 1))) ?? AnySequence([])
        return rows.map { row in
            Store(
                id: row[storeID],
                name: row[storeName],
                flippID: row[storeFlippID],
                isSelected: row[storeIsSelected] == 1,
                lastSyncedAt: row[storeLastSynced]
            )
        }
    }

    // MARK: - Item helpers

    // Inserts or updates an item by normalised name.
    // Returns the item's database ID.
    @discardableResult
    func upsertItem(nameNormalised: String, nameDisplay: String) -> Int64 {
        if let existing = try? db.pluck(itemsTable.filter(itemNameNormalised == nameNormalised)) {
            return existing[itemID]
        }
        let id = try? db.run(itemsTable.insert(
            itemNameNormalised <- nameNormalised,
            itemNameDisplay <- nameDisplay,
            itemCreatedAt <- Date()
        ))
        return id ?? 0
    }

    // Ensures a user_items row exists for the given item.
    func upsertUserItem(itemIDValue: Int64) {
        let existing = userItemsTable.filter(userItemsItemID == itemIDValue)
        if (try? db.scalar(existing.count)) == 0 {
            try? db.run(userItemsTable.insert(
                userItemsItemID <- itemIDValue,
                userItemsAddedDate <- Date(),
                userItemsIsActive <- 1
            ))
        }
    }

    // Returns all active user items, sorted by next restock date ascending.
    func fetchUserItems() -> [UserItem] {
        let query = userItemsTable
            .join(itemsTable, on: userItemsItemID == itemID)
            .filter(userItemsIsActive == 1)
        let rows = (try? db.prepare(query)) ?? AnySequence([])
        return rows.map { row in
            UserItem(
                id: row[userItemID],
                itemID: row[userItemsItemID],
                nameDisplay: row[itemNameDisplay],
                lastPurchasedDate: row[userItemsLastPurchasedDate],
                lastPurchasedPrice: row[userItemsLastPurchasedPrice],
                inferredCycleDays: row[userItemsReplenishInferred].map { Int($0) },
                userOverrideCycleDays: row[userItemsReplenishOverride].map { Int($0) },
                nextRestockDate: row[userItemsNextRestockDate],
                // Fix P1-5: per-item alert check, not global count.
                hasActiveAlert: hasAlertFiredForItem(itemID: row[userItemsItemID])
            )
        }
    }

    // MARK: - Purchase helpers

    // Fix P0-1: markPurchased() is now atomic.
    // It writes purchase_history AND updates user_items in a single transaction.
    // Do NOT call insertPurchase() separately after this — that would create a duplicate row.
    func markPurchased(itemID: Int64, priceAtPurchase: Double?) {
        let today = Date()
        do {
            try db.transaction {
                // Update the user_items row with today's purchase date.
                let userItem = userItemsTable.filter(userItemsItemID == itemID)
                try db.run(userItem.update(
                    userItemsLastPurchasedDate <- today,
                    userItemsLastPurchasedPrice <- priceAtPurchase,
                    userItemsNextRestockDate <- nil  // Reset; recalculated below.
                ))
                // Write a purchase_history row so replenishment logic has data.
                try db.run(purchaseHistoryTable.insert(
                    purchaseItemID <- itemID,
                    purchasedAt <- today,
                    purchasePrice <- priceAtPurchase,
                    purchaseSource <- "manual"
                ))
            }
            recalculateReplenishment(itemID: itemID)
        } catch {
            print("[DatabaseManager] markPurchased failed for itemID \(itemID): \(error)")
        }
    }

    // Recalculates the inferred replenishment cycle for an item
    // using the median interval between its purchase_history rows.
    // Also updates next_restock_date on user_items.
    func recalculateReplenishment(itemID: Int64) {
        let rows = (try? db.prepare(
            purchaseHistoryTable
                .filter(purchaseItemID == itemID)
                .order(purchasedAt.asc)
        )) ?? AnySequence([])

        let dates = rows.compactMap { $0[purchasedAt] as Date? }
        guard dates.count >= 2 else { return }

        // Calculate day-intervals between consecutive purchases.
        var intervals: [Int] = []
        for i in 1..<dates.count {
            let days = Calendar.current.dateComponents([.day], from: dates[i - 1], to: dates[i]).day ?? 0
            if days > 0 { intervals.append(days) }
        }
        guard !intervals.isEmpty else { return }

        let sorted = intervals.sorted()
        // TODO: use true median for even counts: (sorted[n/2-1] + sorted[n/2]) / 2 — P2-1
        let median = sorted[sorted.count / 2]

        let lastPurchased = dates.last!
        let nextRestock = Calendar.current.date(byAdding: .day, value: median, to: lastPurchased)

        try? db.run(
            userItemsTable.filter(userItemsItemID == itemID).update(
                userItemsReplenishInferred <- Int64(median),
                userItemsNextRestockDate <- nextRestock
            )
        )
    }

    // Returns the current lowest price for an item across all selected stores.
    // Used by HomeViewModel when recording the price at time of purchase.
    func currentLowestPrice(for itemID: Int64) -> Double? {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let row = try? db.pluck(
            priceHistoryTable
                .filter(priceHistItemID == itemID && priceHistDate >= sevenDaysAgo)
                .order(priceHistPrice.asc)
        )
        return row?[priceHistPrice]
    }

    // MARK: - Flyer sale helpers

    // Fix P1-8: INSERT OR IGNORE — unique index on (item_id, store_id, sale_start_date, sale_price)
    // prevents duplicate rows from accumulating on every daily sync.
    // On an existing row: only fetched_at is refreshed.
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
        // Refresh fetched_at on the existing row (ignore fires on duplicate).
        let existing = flyerSalesTable.filter(
            flyerItemID == itemID && flyerStoreID == storeID &&
            flyerStartDate == startDate && flyerSalePrice == salePrice
        )
        try? db.run(existing.update(flyerFetchedAt <- Date()))
    }

    // Returns all flyer sales currently active today for a given item.
    func fetchActiveSales(for itemID: Int64) -> [FlyerSale] {
        let today = Date()
        let query = flyerSalesTable.filter(
            flyerItemID == itemID &&
            flyerStartDate <= today
        )
        let rows = (try? db.prepare(query)) ?? AnySequence([])
        return rows.compactMap { row in
            let end = row[flyerEndDate]
            if let end = end, end < today { return nil }  // expired
            return FlyerSale(
                id: row[flyerID],
                itemID: row[flyerItemID],
                storeID: row[flyerStoreID],
                salePrice: row[flyerSalePrice],
                validFrom: row[flyerStartDate],
                validTo: row[flyerEndDate],
                source: row[flyerSource],
                fetchedAt: row[flyerFetchedAt]
            )
        }
    }

    // MARK: - Alert log helpers

    // Fix P1-5: per-item check, not a global count.
    // Returns true when at least one alert for this specific item fired today.
    func hasAlertFiredForItem(itemID: Int64) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let count = (try? db.scalar(
            alertLogTable.filter(alertItemID == itemID && alertFiredAt >= startOfToday).count
        )) ?? 0
        return count > 0
    }

    // Returns how many alerts (any type, any item) have fired today.
    // Used by AlertEngine to enforce the 3-alert daily cap.
    func alertsFiredToday() -> Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return (try? db.scalar(
            alertLogTable.filter(alertFiredAt >= startOfToday).count
        )) ?? 0
    }

    // Writes a new alert_log row. Call this BEFORE firing the UNUserNotificationCenter
    // request — that way cap + dedup work correctly even if permission is denied.
    func logAlert(itemID: Int64, storeID: Int64, type: String,
                  price: Double, saleEventID: Int64?, notificationID: String?) {
        try? db.run(alertLogTable.insert(
            alertItemID     <- itemID,
            alertStoreID    <- storeID,
            alertType       <- type,
            alertPrice      <- price,
            alertFiredAt    <- Date(),
            alertSaleEventID <- saleEventID,
            alertNotifID    <- notificationID
        ))
    }

    // MARK: - Data hygiene

    // Deletes old flyer_sales and alert_log rows to keep the DB small.
    // Call after each daily Flipp sync (BackgroundSyncManager).
    func runDataHygiene() {
        // Remove flyer sales that expired more than 30 days ago.
        try? db.execute("""
            DELETE FROM flyer_sales
            WHERE sale_end_date < date('now', '-30 days')
        """)
        // Remove alert log entries older than 60 days.
        try? db.execute("""
            DELETE FROM alert_log
            WHERE fired_at < date('now', '-60 days')
        """)
    }
}
