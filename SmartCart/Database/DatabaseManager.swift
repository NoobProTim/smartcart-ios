// DatabaseManager.swift — SmartCart/Database/DatabaseManager.swift
//
// The single point of contact between the app and the local SQLite database.
// All reads and writes go through this class — no raw SQLite anywhere else.
//
// Uses SQLite.swift (stephencelis/SQLite.swift 0.15.x).
// Access via DatabaseManager.shared (singleton).
//
// Mutation methods (markPurchased, recalculateReplenishment) live in
// DatabaseManager+Fixes.swift — they own the quantity-aware, atomic versions.

import Foundation
import SQLite

final class DatabaseManager {

    static let shared = DatabaseManager()
    /// internal so +Fixes / +Alerts / +Purchases extensions can reach it.
    var db: Connection!

    private init() {
        do {
            let docURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = docURL.appendingPathComponent("smartcart.sqlite3")
            db = try Connection(dbURL.path)
            try db.execute("PRAGMA journal_mode = WAL")
            try db.execute("PRAGMA foreign_keys = ON")
            runMigrations()
        } catch {
            fatalError("[DatabaseManager] Failed to open SQLite: \(error)")
        }
    }

    // MARK: - Migrations

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

            // user_items (M1 base schema)
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

            // purchase_history (M1 base schema)
            try db.run(purchaseHistoryTable.create(ifNotExists: true) { t in
                t.column(purchaseID, primaryKey: .autoincrement)
                t.column(purchaseItemID, references: itemsTable, itemID)
                t.column(purchaseStoreID)
                t.column(purchasePrice)
                t.column(purchasedAt)
                t.column(purchaseSource, defaultValue: "manual")
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

            // M2: additive migrations for existing databases (is_seasonal, qty).
            // ALTER TABLE is a no-op if the column already exists; errors are swallowed.
            applyM2Migrations()

        } catch {
            print("[DatabaseManager] Migration error: \(error)")
        }
        applyM3Migrations()
    }

    /// M2 additive migrations. Safe to call repeatedly.
    private func applyM2Migrations() {
        try? db.execute("ALTER TABLE user_items ADD COLUMN is_seasonal INTEGER NOT NULL DEFAULT 0")
        try? db.execute("ALTER TABLE purchase_history ADD COLUMN qty INTEGER NOT NULL DEFAULT 1")
    }

    /// M3: grocery_list table (ifNotExists — safe on existing databases).
    private func applyM3Migrations() {
        _ = try? db.run(groceryListTable.create(ifNotExists: true) { t in
            t.column(groceryListID,        primaryKey: .autoincrement)
            t.column(groceryListItemID)
            t.column(groceryListPrice)
            t.column(groceryListAddedAt)
            t.column(groceryListPurchased, defaultValue: 0)
            t.foreignKey(groceryListItemID, references: itemsTable, itemID, delete: .cascade)
        })
    }

    private func seedDefaultSettings() {
        for (key, value) in Schema.defaultSettings {
            let row = userSettingsTable.filter(settingKey == key)
            if (try? db.scalar(row.count)) == 0 {
                _ = try? db.run(userSettingsTable.insert(settingKey <- key, settingValue <- value))
            }
        }
    }

    // MARK: - Settings helpers

    func getSetting(key: String) -> String? {
        let row = userSettingsTable.filter(settingKey == key)
        return try? db.pluck(row).flatMap { $0[settingValue] }
    }

    func setSetting(key: String, value: String?) {
        _ = try? db.run(userSettingsTable.insert(or: .replace,
            settingKey <- key, settingValue <- value))
    }

    func deleteSetting(key: String) {
        _ = try? db.run(userSettingsTable.filter(settingKey == key).delete())
    }

    // MARK: - Store helpers

    func fetchSelectedStoreNames() -> [String] {
        let rows = (try? db.prepare(userSettingsTable)) ?? AnySequence([])
        let selectedIDs: [Int64] = rows.compactMap { row in
            let key = row[settingKey]
            guard key.hasPrefix("store_selected_"),
                  row[settingValue] == "1",
                  let idPart = key.split(separator: "_").last,
                  let id = Int64(idPart) else { return nil }
            return id
        }
        return selectedIDs.compactMap { id in
            let row = try? db.pluck(storesTable.filter(storeID == id))
            return row?[storeName]
        }
    }

    @discardableResult
    func upsertStore(name: String) -> Int64 {
        if let existing = try? db.pluck(storesTable.filter(storeName == name)) {
            return existing[storeID]
        }
        return (try? db.run(storesTable.insert(
            storeName <- name,
            storeIsSelected <- 1
        ))) ?? 0
    }

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

    @discardableResult
    func upsertItem(nameNormalised: String, nameDisplay: String) -> Int64 {
        if let existing = try? db.pluck(itemsTable.filter(itemNameNormalised == nameNormalised)) {
            return existing[itemID]
        }
        return (try? db.run(itemsTable.insert(
            itemNameNormalised <- nameNormalised,
            itemNameDisplay    <- nameDisplay,
            itemCreatedAt      <- Date()
        ))) ?? 0
    }

    func upsertUserItem(itemIDValue: Int64) {
        let existing = userItemsTable.filter(userItemsItemID == itemIDValue)
        if (try? db.scalar(existing.count)) == 0 {
            _ = try? db.run(userItemsTable.insert(
                userItemsItemID    <- itemIDValue,
                userItemsAddedDate <- Date(),
                userItemsIsActive  <- 1
            ))
        }
    }

    // MARK: - findItem / insertItem / addToWatchlist / insertPurchase

    // Looks up an item by its normalised name. Returns the itemID if found, nil otherwise.
    func findItem(normalisedName: String) -> Int64? {
        guard let row = try? db.pluck(itemsTable.filter(itemNameNormalised == normalisedName)) else { return nil }
        return row[itemID]
    }

    // Inserts a new item row and returns its new itemID.
    // Callers should call findItem first to avoid duplicate errors.
    @discardableResult
    func insertItem(normalisedName: String, displayName: String) -> Int64 {
        return (try? db.run(itemsTable.insert(
            itemNameNormalised <- normalisedName,
            itemNameDisplay    <- displayName,
            itemCreatedAt      <- Date()
        ))) ?? 0
    }

    // Adds an item to the user's Smart List. Safe to call if already present.
    func addToWatchlist(itemID itemIDValue: Int64) {
        upsertUserItem(itemIDValue: itemIDValue)
    }

    // Records a purchase with a date string (yyyy-MM-dd from DateHelper.todayString()).
    // Used by ReceiptReviewView and AlertDetailView.
    func insertPurchase(itemID: Int64, storeID: Int64?, price: Double, date: String, source: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let purchaseDate = fmt.date(from: date) ?? Date()
        markPurchasedOnDate(itemID: itemID, priceAtPurchase: price, storeID: storeID,
                            date: purchaseDate, source: source)
    }

    // MARK: - Fetch user items

    /// Returns all active tracked items joined with their display name.
    /// isSeasonal reads the M2 column (defaults 0/false on old rows).
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
                hasActiveAlert: hasAlertFiredForItem(itemID: row[userItemsItemID]),
                isSeasonal: (row[userItemsIsSeasonal] ?? 0) == 1
            )
        }
    }

    // MARK: - Price helpers

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

    /// Returns all flyer sales currently active today for a given item.
    /// Includes regularPrice so FlyerSale.discountPercent() works correctly.
    func fetchActiveSales(for itemID: Int64) -> [FlyerSale] {
        let today = Date()
        let query = flyerSalesTable.filter(
            flyerItemID == itemID && flyerStartDate <= today
        )
        let rows = (try? db.prepare(query)) ?? AnySequence([])
        return rows.compactMap { row in
            let end = row[flyerEndDate]
            if let end = end, end < today { return nil }   // expired
            return FlyerSale(
                id:           row[flyerID],
                itemID:       row[flyerItemID],
                storeID:      row[flyerStoreID],
                salePrice:    row[flyerSalePrice],
                regularPrice: row[flyerRegularPrice],      // Fix: was missing
                validFrom:    row[flyerStartDate],
                validTo:      row[flyerEndDate],
                source:       row[flyerSource],
                fetchedAt:    row[flyerFetchedAt]
            )
        }
    }

    // MARK: - Alert log helpers

    func alertsFiredToday() -> Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return (try? db.scalar(
            alertLogTable.filter(alertFiredAt >= startOfToday).count
        )) ?? 0
    }

    func logAlert(itemID: Int64, storeID: Int64, type: String,
                  price: Double, saleEventID: Int64?, notificationID: String?) {
        _ = try? db.run(alertLogTable.insert(
            alertItemID      <- itemID,
            alertStoreID     <- storeID,
            alertType        <- type,
            alertPrice       <- price,
            alertFiredAt     <- Date(),
            alertSaleEventID <- saleEventID,
            alertNotifID     <- notificationID
        ))
    }

    // MARK: - Data hygiene

    func runDataHygiene() {
        try? db.execute("""
            DELETE FROM flyer_sales
            WHERE sale_end_date < date('now', '-30 days')
        """)
        try? db.execute("""
            DELETE FROM alert_log
            WHERE fired_at < date('now', '-60 days')
        """)
    }
}
