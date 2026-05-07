// DatabaseManager.swift
// SmartCart — Database/DatabaseManager.swift
//
// The single point of contact for all database reads and writes.
// Every View and Service goes through this class — nothing else touches SQLite directly.
// Uses the singleton pattern: always access via DatabaseManager.shared.

import Foundation
import SQLite

final class DatabaseManager {

    // The one shared instance used everywhere in the app.
    static let shared = DatabaseManager()

    // The live connection to the SQLite file on disk.
    private var db: Connection!

    private init() {}

    // ─────────────────────────────────────────────
    // MARK: - Setup
    // ─────────────────────────────────────────────

    /// Call once from SmartCartApp on launch.
    /// Opens (or creates) the SQLite file and runs all table migrations.
    func setup() {
        do {
            let path = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("smartcart.sqlite").path
            db = try Connection(path)
            db.busyTimeout = 5
            try runMigrations(db: db)
        } catch {
            fatalError("[DatabaseManager] Failed to open database: \(error)")
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Stores
    // ─────────────────────────────────────────────

    /// Inserts a new store or updates its name if it already exists.
    /// Returns the row ID so the caller can reference it immediately.
    @discardableResult
    func upsertStore(name: String) -> Int64 {
        do {
            let existing = storesTable.filter(storeName == name)
            if let row = try db.pluck(existing) {
                return row[storeID]
            }
            return try db.run(storesTable.insert(
                storeName       <- name,
                storeIsSelected <- true
            ))
        } catch {
            print("[DatabaseManager] upsertStore failed: \(error)")
            return -1
        }
    }

    /// Returns all stores the user has marked as selected.
    func fetchSelectedStores() -> [Store] {
        let rows = (try? db.prepare(storesTable.filter(storeIsSelected == true))) ?? AnySequence([])
        return rows.map { row in
            Store(
                id: row[storeID],
                name: row[storeName],
                flippID: row[storeFlippID],
                isSelected: row[storeIsSelected],
                lastSyncedAt: row[storeLastSynced]
            )
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Items
    // ─────────────────────────────────────────────

    /// Inserts or updates a canonical Item row, then ensures a user_items row exists.
    /// Called after the user confirms an item on the Receipt Review screen.
    @discardableResult
    func upsertItem(normalisedName: String, displayName: String) -> Int64 {
        do {
            let existing = itemsTable.filter(itemNameNormalised == normalisedName)
            let id: Int64
            if let row = try db.pluck(existing) {
                id = row[itemID]
            } else {
                id = try db.run(itemsTable.insert(
                    itemNameNormalised  <- normalisedName,
                    itemNameDisplay     <- displayName,
                    itemCreatedAt       <- Date()
                ))
            }
            // Make sure this item appears in the user's tracked list
            try db.run(userItemsTable.insert(or: .ignore, userItemsItemID <- id))
            return id
        } catch {
            print("[DatabaseManager] upsertItem failed: \(error)")
            return -1
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - User Items (Smart List)
    // ─────────────────────────────────────────────

    /// Returns all items on the user's Smart List, joined with item details.
    func fetchUserItems() -> [UserItem] {
        let query = userItemsTable
            .join(itemsTable, on: userItemsItemID == itemID)
            .order(userItemsNextRestockDate.asc)
        let rows = (try? db.prepare(query)) ?? AnySequence([])
        return rows.map { row in
            UserItem(
                id: row[userItemID],
                itemID: row[userItemsItemID],
                nameDisplay: row[itemNameDisplay],
                lastPurchasedDate: row[userItemsLastPurchasedDate],
                lastPurchasedPrice: row[userItemsLastPurchasedPrice],
                inferredCycleDays: row[userItemsInferredCycleDays],
                userOverrideCycleDays: row[userItemsOverrideCycleDays],
                nextRestockDate: row[userItemsNextRestockDate],
                hasActiveAlert: hasAlertFiredForItem(itemID: row[userItemsItemID])
            )
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Purchase History
    // ─────────────────────────────────────────────

    /// Records a confirmed purchase. Atomic — writes both user_items and purchase_history
    /// in a single transaction so they can never get out of sync.
    func markPurchased(itemID: Int64, priceAtPurchase: Double?) {
        let today = Date()
        do {
            try db.transaction {
                let userItem = userItemsTable.filter(userItemsItemID == itemID)
                try db.run(userItem.update(
                    userItemsLastPurchasedDate  <- today,
                    userItemsLastPurchasedPrice <- priceAtPurchase,
                    userItemsNextRestockDate    <- nil
                ))
                try db.run(purchaseHistoryTable.insert(
                    purchaseItemID  <- itemID,
                    purchasedAt     <- today,
                    purchasePrice   <- priceAtPurchase,
                    purchaseSource  <- "manual"
                ))
            }
            recalculateReplenishment(itemID: itemID)
        } catch {
            print("[DatabaseManager] markPurchased failed for itemID \(itemID): \(error)")
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Price History
    // ─────────────────────────────────────────────

    /// Stores a regular shelf-price observation. Sale prices go to insertFlyerSale() instead.
    func insertPriceHistory(itemID: Int64, storeID: Int64, price: Double, source: String) {
        try? db.run(priceHistoryTable.insert(
            priceHistItemID   <- itemID,
            priceHistStoreID  <- storeID,
            priceHistPrice    <- price,
            priceHistObserved <- Date(),
            priceHistSource   <- source
        ))
    }

    /// Returns the average price for an item across the last 90 days.
    /// Used by AlertEngine to determine if a current price is a genuine historical low.
    func rollingAverage90(itemID: Int64) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let query = priceHistoryTable
            .filter(priceHistItemID == itemID && priceHistObserved >= cutoff)
            .select(priceHistPrice.average)
        return (try? db.scalar(query)) ?? nil
    }

    /// Returns the current lowest price for an item across all selected stores.
    func currentLowestPrice(for itemID: Int64) -> Double? {
        let selectedIDs = fetchSelectedStores().map { $0.id }
        guard !selectedIDs.isEmpty else { return nil }
        let query = priceHistoryTable
            .filter(priceHistItemID == itemID && selectedIDs.contains(priceHistStoreID))
            .select(priceHistPrice.min)
        return (try? db.scalar(query)) ?? nil
    }

    // ─────────────────────────────────────────────
    // MARK: - Flyer Sales
    // ─────────────────────────────────────────────

    /// Inserts a sale event, ignoring duplicates (same item/store/date/price).
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
        // Update fetched_at on existing row so we know it was seen on this sync
        let existing = flyerSalesTable.filter(
            flyerItemID == itemID && flyerStoreID == storeID &&
            flyerStartDate == startDate && flyerSalePrice == salePrice
        )
        try? db.run(existing.update(flyerFetchedAt <- Date()))
    }

    /// Returns all active sale events for the user's tracked items.
    func fetchActiveFlyerSales() -> [FlyerSale] {
        let now = Date()
        let rows = (try? db.prepare(flyerSalesTable.filter(flyerStartDate <= now))) ?? AnySequence([])
        return rows.compactMap { row in
            let sale = FlyerSale(
                id: row[flyerID], itemID: row[flyerItemID], storeID: row[flyerStoreID],
                salePrice: row[flyerSalePrice], validFrom: row[flyerStartDate],
                validTo: row[flyerEndDate], source: row[flyerSource], fetchedAt: row[flyerFetchedAt]
            )
            return sale.isActive ? sale : nil
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Alert Log
    // ─────────────────────────────────────────────

    /// Returns how many alerts have fired today across all items.
    func alertsFiredToday() -> Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return (try? db.scalar(alertLogTable.filter(alertFiredAt >= startOfToday).count)) ?? 0
    }

    /// Returns true if an alert has already fired for this specific item today.
    func hasAlertFiredForItem(itemID: Int64) -> Bool {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let count = (try? db.scalar(
            alertLogTable.filter(alertItemID == itemID && alertFiredAt >= startOfToday).count
        )) ?? 0
        return count > 0
    }

    /// Records a fired alert. Written BEFORE calling UNUserNotificationCenter so the
    /// daily cap and dedup work even when notification permission is denied.
    func insertAlertLog(itemID: Int64, type: String, triggerPrice: Double,
                        notificationID: String?, saleEventID: Int64?) {
        try? db.run(alertLogTable.insert(
            alertItemID       <- itemID,
            alertType         <- type,
            alertTriggerPrice <- triggerPrice,
            alertFiredAt      <- Date(),
            alertNotifID      <- notificationID,
            alertSaleEventID  <- saleEventID
        ))
    }

    // ─────────────────────────────────────────────
    // MARK: - User Settings
    // ─────────────────────────────────────────────

    func getSetting(key: String) -> String? {
        let row = try? db.pluck(userSettingsTable.filter(settingKey == key))
        return row?[settingValue]
    }

    func setSetting(key: String, value: String) {
        try? db.run(userSettingsTable.insert(or: .replace, settingKey <- key, settingValue <- value))
    }

    func deleteSetting(key: String) {
        try? db.run(userSettingsTable.filter(settingKey == key).delete())
    }

    // ─────────────────────────────────────────────
    // MARK: - Replenishment
    // ─────────────────────────────────────────────

    /// Recalculates the median purchase interval for an item and writes it back to user_items.
    /// Called after every confirmed purchase so the Smart List sort order stays accurate.
    func recalculateReplenishment(itemID: Int64) {
        let rows = (try? db.prepare(
            purchaseHistoryTable
                .filter(purchaseItemID == itemID)
                .order(purchasedAt.asc)
        )) ?? AnySequence([])
        let dates = rows.map { $0[purchasedAt] }
        guard dates.count >= 2 else { return }

        var intervals: [Int] = []
        for i in 1..<dates.count {
            let days = Calendar.current.dateComponents([.day], from: dates[i-1], to: dates[i]).day ?? 0
            if days > 0 { intervals.append(days) }
        }
        guard !intervals.isEmpty else { return }

        let sorted = intervals.sorted()
        // TODO: use true median — for even counts, average the two middle values
        let median = sorted[sorted.count / 2]

        let lastDate = dates.last!
        let nextRestock = Calendar.current.date(byAdding: .day, value: median, to: lastDate)

        let userItem = userItemsTable.filter(userItemsItemID == itemID)
        try? db.run(userItem.update(
            userItemsInferredCycleDays <- median,
            userItemsNextRestockDate   <- nextRestock
        ))
    }
}
