// Schema.swift
// SmartCart — Database/Schema.swift
//
// Defines every SQLite table as a SQLite.swift Table + Expression set.
// Also holds runMigrations() which creates all tables on first launch.
// If you add a new column, add a new migration step at the bottom of runMigrations()
// rather than changing the CREATE TABLE — this keeps existing installs safe.

import Foundation
import SQLite

// ─────────────────────────────────────────────
// MARK: - Table handles
// ─────────────────────────────────────────────

// Each constant is a reference to a table in the SQLite file.
// Think of them like pointers — they don't hold data, just describe the table.
let storesTable           = Table("stores")
let itemsTable            = Table("items")
let userItemsTable        = Table("user_items")
let purchaseHistoryTable  = Table("purchase_history")
let priceHistoryTable     = Table("price_history")
let flyerSalesTable       = Table("flyer_sales")
let alertLogTable         = Table("alert_log")
let userStoresTable       = Table("user_stores")
let userSettingsTable     = Table("user_settings")

// ─────────────────────────────────────────────
// MARK: - Column expressions
// ─────────────────────────────────────────────

// stores
let storeID         = Expression<Int64>("id")
let storeName       = Expression<String>("name")
let storeFlippID    = Expression<String?>("flipp_id")
let storeIsSelected = Expression<Bool>("is_selected")
let storeLastSynced = Expression<Date?>("last_synced_at")

// items
let itemID              = Expression<Int64>("id")
let itemNameNormalised  = Expression<String>("name_normalised")
let itemNameDisplay     = Expression<String>("name_display")
let itemCategory        = Expression<String?>("category")
let itemUnit            = Expression<String?>("unit")
let itemCreatedAt       = Expression<Date>("created_at")

// user_items
let userItemID                  = Expression<Int64>("id")
let userItemsItemID             = Expression<Int64>("item_id")
let userItemsLastPurchasedDate  = Expression<Date?>("last_purchased_date")
let userItemsLastPurchasedPrice = Expression<Double?>("last_purchased_price")
let userItemsInferredCycleDays  = Expression<Int?>("inferred_cycle_days")
let userItemsOverrideCycleDays  = Expression<Int?>("user_override_cycle_days")
let userItemsNextRestockDate    = Expression<Date?>("next_restock_date")

// purchase_history
let purchaseID     = Expression<Int64>("id")
let purchaseItemID = Expression<Int64>("item_id")
let purchasedAt    = Expression<Date>("purchased_at")
let purchasePrice  = Expression<Double?>("price")
let purchaseSource = Expression<String>("source")
let purchaseStoreID = Expression<Int64?>("store_id")

// price_history
let priceHistID       = Expression<Int64>("id")
let priceHistItemID   = Expression<Int64>("item_id")
let priceHistStoreID  = Expression<Int64>("store_id")
let priceHistPrice    = Expression<Double>("price")
let priceHistObserved = Expression<Date>("observed_at")
let priceHistSource   = Expression<String>("source")

// flyer_sales
let flyerID          = Expression<Int64>("id")
let flyerItemID      = Expression<Int64>("item_id")
let flyerStoreID     = Expression<Int64>("store_id")
let flyerSalePrice   = Expression<Double>("sale_price")
let flyerRegPrice    = Expression<Double?>("regular_price")
let flyerStartDate   = Expression<Date>("sale_start_date")
let flyerEndDate     = Expression<Date?>("sale_end_date")
let flyerSource      = Expression<String>("source")
let flyerFetchedAt   = Expression<Date>("fetched_at")

// alert_log
let alertLogID       = Expression<Int64>("id")
let alertItemID      = Expression<Int64>("item_id")
let alertType        = Expression<String>("alert_type")
let alertTriggerPrice = Expression<Double>("trigger_price")
let alertFiredAt     = Expression<Date>("fired_at")
let alertNotifID     = Expression<String?>("notification_id")
let alertSaleEventID = Expression<Int64?>("sale_event_id")

// user_stores
let userStoreID    = Expression<Int64>("id")
let userStoreStoreID = Expression<Int64>("store_id")
let userStoreAddedAt = Expression<Date>("added_at")

// user_settings
let settingKey   = Expression<String>("key")
let settingValue = Expression<String>("value")

// ─────────────────────────────────────────────
// MARK: - Migration runner
// ─────────────────────────────────────────────

/// Call once at app launch (from DatabaseManager.shared.setup()).
/// Creates all tables if they don't exist. Safe to run on every launch.
func runMigrations(db: Connection) throws {

    // stores — one row per grocery chain
    try db.run(storesTable.create(ifNotExists: true) { t in
        t.column(storeID, primaryKey: .autoincrement)
        t.column(storeName, unique: true)
        t.column(storeFlippID)
        t.column(storeIsSelected, defaultValue: false)
        t.column(storeLastSynced)
    })

    // items — canonical product catalogue
    try db.run(itemsTable.create(ifNotExists: true) { t in
        t.column(itemID, primaryKey: .autoincrement)
        t.column(itemNameNormalised, unique: true)
        t.column(itemNameDisplay)
        t.column(itemCategory)
        t.column(itemUnit)
        t.column(itemCreatedAt)
    })

    // user_items — the user's personal tracked list
    try db.run(userItemsTable.create(ifNotExists: true) { t in
        t.column(userItemID, primaryKey: .autoincrement)
        t.column(userItemsItemID, unique: true, references: itemsTable, itemID)
        t.column(userItemsLastPurchasedDate)
        t.column(userItemsLastPurchasedPrice)
        t.column(userItemsInferredCycleDays)
        t.column(userItemsOverrideCycleDays)
        t.column(userItemsNextRestockDate)
    })

    // purchase_history — every confirmed buy event
    try db.run(purchaseHistoryTable.create(ifNotExists: true) { t in
        t.column(purchaseID, primaryKey: .autoincrement)
        t.column(purchaseItemID, references: itemsTable, itemID)
        t.column(purchasedAt)
        t.column(purchasePrice)
        t.column(purchaseSource)
        t.column(purchaseStoreID)
    })

    // price_history — regular shelf prices only (NOT sale prices)
    try db.run(priceHistoryTable.create(ifNotExists: true) { t in
        t.column(priceHistID, primaryKey: .autoincrement)
        t.column(priceHistItemID, references: itemsTable, itemID)
        t.column(priceHistStoreID, references: storesTable, storeID)
        t.column(priceHistPrice)
        t.column(priceHistObserved)
        t.column(priceHistSource)
    })

    // flyer_sales — time-bounded promotional events from Flipp
    // Separate from price_history to avoid contaminating the 90-day rolling average.
    try db.run(flyerSalesTable.create(ifNotExists: true) { t in
        t.column(flyerID, primaryKey: .autoincrement)
        t.column(flyerItemID, references: itemsTable, itemID)
        t.column(flyerStoreID, references: storesTable, storeID)
        t.column(flyerSalePrice)
        t.column(flyerRegPrice)
        t.column(flyerStartDate)
        t.column(flyerEndDate)
        t.column(flyerSource)
        t.column(flyerFetchedAt)
    })

    // alert_log — every alert that fired (written BEFORE sending push)
    try db.run(alertLogTable.create(ifNotExists: true) { t in
        t.column(alertLogID, primaryKey: .autoincrement)
        t.column(alertItemID, references: itemsTable, itemID)
        t.column(alertType)        // 'historical_low' | 'sale' | 'expiry' | 'combined'
        t.column(alertTriggerPrice)
        t.column(alertFiredAt)
        t.column(alertNotifID)
        t.column(alertSaleEventID) // FK to flyer_sales.id for dedup
    })

    // user_stores — join table (currently not written during onboarding — see P2-3)
    try db.run(userStoresTable.create(ifNotExists: true) { t in
        t.column(userStoreID, primaryKey: true)
        t.column(userStoreStoreID, unique: true, references: storesTable, storeID)
        t.column(userStoreAddedAt)
    })

    // user_settings — key/value store for app preferences
    try db.run(userSettingsTable.create(ifNotExists: true) { t in
        t.column(settingKey, primaryKey: true)
        t.column(settingValue)
    })

    // Seed default settings on first launch
    let defaults: [(String, String)] = [
        ("onboarding_complete",    "0"),
        ("notification_enabled",   "0"),
        ("user_postal_code",        ""),
        ("min_discount_percent",   "15"),
        ("alert_on_historical_low","1"),
        ("alert_on_sale",          "1"),
        ("alert_on_expiry",        "1"),
        ("expiry_reminder_days",   "2"),
        ("daily_alert_cap",        "3")
        // NOTE: Daily alert cap is enforced by counting alert_log rows where fired_at = today.
        // Do NOT track separately in user_settings.
    ]
    for (key, value) in defaults {
        try? db.run(userSettingsTable.insert(or: .ignore, settingKey <- key, settingValue <- value))
    }
}
