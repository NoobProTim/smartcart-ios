// Schema.swift — SmartCart/Database/Schema.swift
//
// Defines every SQLite table, column, and index for SmartCart.
// Uses SQLite.swift (stephencelis/SQLite.swift 0.15.x) typed expressions.
// Call DatabaseManager.shared.runMigrations() once on first launch.
//
// IMPORTANT: Do not change column names without also updating
// DatabaseManager.swift and the corresponding Swift Model struct.

import Foundation
import SQLite

// MARK: - Table declarations

let storesTable          = Table("stores")
let itemsTable           = Table("items")
let userItemsTable       = Table("user_items")
let purchaseHistoryTable = Table("purchase_history")
let priceHistoryTable    = Table("price_history")
let flyerSalesTable      = Table("flyer_sales")
let alertLogTable        = Table("alert_log")
let userStoresTable      = Table("user_stores")
let userSettingsTable    = Table("user_settings")

// MARK: - stores columns
let storeID         = Expression<Int64>("id")
let storeName       = Expression<String>("name")
let storeLogoURL    = Expression<String?>("logo_url")
let storeFlippID    = Expression<String?>("flipp_id")
let storeIsSelected = Expression<Int64>("is_selected")
let storeLastSynced = Expression<Date?>("last_synced_at")

// MARK: - items columns
let itemID             = Expression<Int64>("id")
let itemNameNormalised = Expression<String>("name_normalised")
let itemNameDisplay    = Expression<String>("name_display")
let itemCategory       = Expression<String?>("category")
let itemUnit           = Expression<String?>("unit")
let itemCreatedAt      = Expression<Date>("created_at")

// MARK: - user_items columns
let userItemID                  = Expression<Int64>("id")
let userItemsItemID             = Expression<Int64>("item_id")
let userItemsAddedDate          = Expression<Date>("added_date")
let userItemsLastPurchasedDate  = Expression<Date?>("last_purchased_date")
let userItemsLastPurchasedPrice = Expression<Double?>("last_purchased_price")
let userItemsLastStoreID        = Expression<Int64?>("last_purchased_store_id")
let userItemsReplenishInferred  = Expression<Int64?>("replenishment_inferred")
let userItemsReplenishOverride  = Expression<Int64?>("replenishment_override")
let userItemsNextRestockDate    = Expression<Date?>("next_restock_date")
let userItemsIsActive           = Expression<Int64>("is_active")
/// 0 = normal, 1 = irregular purchase pattern — suppresses restock alerts.
/// Added in migration M2. Use applyM2Migration() in runMigrations().
let userItemsIsSeasonal         = Expression<Int64?>("is_seasonal")

// MARK: - purchase_history columns
let purchaseID     = Expression<Int64>("id")
let purchaseItemID = Expression<Int64>("item_id")
let purchaseStoreID = Expression<Int64?>("store_id")
let purchasePrice  = Expression<Double?>("price")
let purchasedAt    = Expression<Date>("purchased_at")
let purchaseSource = Expression<String>("source")
/// Number of units bought in one purchase. Added in migration M2.
/// Defaults to 1. ReplenishmentEngine scales the restock clock by this value.
let purchaseQty    = Expression<Int64>("qty")

// MARK: - price_history columns
let priceHistID       = Expression<Int64>("id")
let priceHistItemID   = Expression<Int64>("item_id")
let priceHistStoreID  = Expression<Int64>("store_id")
let priceHistPrice    = Expression<Double>("price")
let priceHistDate     = Expression<Date>("observed_at")
let priceHistSource   = Expression<String>("source")

// MARK: - flyer_sales columns
let flyerID        = Expression<Int64>("id")
let flyerItemID    = Expression<Int64>("item_id")
let flyerStoreID   = Expression<Int64>("store_id")
let flyerSalePrice = Expression<Double>("sale_price")
let flyerRegularPrice = Expression<Double?>("regular_price")
let flyerStartDate = Expression<Date>("sale_start_date")
let flyerEndDate   = Expression<Date?>("sale_end_date")
let flyerSource    = Expression<String>("source")
let flyerFetchedAt = Expression<Date>("fetched_at")

// MARK: - alert_log columns
let alertID        = Expression<Int64>("id")
let alertItemID    = Expression<Int64>("item_id")
let alertStoreID   = Expression<Int64>("store_id")
let alertType      = Expression<String>("alert_type")
let alertPrice     = Expression<Double>("price")
let alertFiredAt   = Expression<Date>("fired_at")
let alertSaleEventID = Expression<Int64?>("sale_event_id")
let alertNotifID   = Expression<String?>("notification_id")

// MARK: - user_settings columns
let settingKey   = Expression<String>("key")
let settingValue = Expression<String?>("value")

// MARK: - Default settings seed values
// These are inserted once on first launch by DatabaseManager.seedDefaultSettings().
let defaultSettings: [(String, String?)] = [
    ("notification_enabled",        "1"),
    ("alert_sensitivity",           "balanced"),
    ("quiet_hours_start",           "22:00"),
    ("quiet_hours_end",             "08:00"),
    ("last_price_refresh",          nil),
    // NOTE: daily_alert_count and daily_alert_date are intentionally omitted.
    // Daily alert cap is enforced by counting alert_log rows where fired_at = today.
    // Do NOT track separately in user_settings.
    ("user_postal_code",            nil),
    ("sale_alerts_enabled",         "1"),
    ("flyer_expiry_reminder",       "1"),
    ("expiry_reminder_days_before", "1"),
    ("sale_alert_restock_only",     "1"),
    ("min_discount_threshold",      "0"),
    ("onboarding_complete",         "0")
]
