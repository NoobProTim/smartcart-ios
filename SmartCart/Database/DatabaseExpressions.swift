// DatabaseExpressions.swift — SmartCart/Database/DatabaseExpressions.swift
//
// Module-level SQLite.swift Table and Expression constants.
// Accessible from DatabaseManager and all its extensions without `self.`.
//
// One constant per column. Column names match the SQL schema exactly.
// Types follow SQLite.swift conventions:
//   Expression<T>  — NOT NULL column
//   Expression<T?> — nullable column

import Foundation
import SQLite

// MARK: - stores

let storesTable     = Table("stores")
let storeID         = Expression<Int64>("id")
let storeName       = Expression<String>("name")
let storeLogoURL    = Expression<String?>("logo_url")
let storeFlippID    = Expression<String?>("flipp_id")
let storeIsSelected = Expression<Int64>("is_selected")
let storeLastSynced = Expression<Date?>("last_synced_at")

// MARK: - items

let itemsTable         = Table("items")
let itemID             = Expression<Int64>("id")
let itemNameNormalised = Expression<String>("name_normalised")
let itemNameDisplay    = Expression<String>("name_display")
let itemCategory       = Expression<String?>("category")
let itemUnit           = Expression<String?>("unit")
let itemCreatedAt      = Expression<Date>("created_at")

// MARK: - user_items

let userItemsTable              = Table("user_items")
let userItemID                  = Expression<Int64>("id")
let userItemsItemID             = Expression<Int64>("item_id")
let userItemsAddedDate          = Expression<Date?>("added_date")
let userItemsLastPurchasedDate  = Expression<Date?>("last_purchased_date")
let userItemsLastPurchasedPrice = Expression<Double?>("last_purchased_price")
let userItemsLastStoreID        = Expression<Int64?>("last_store_id")
let userItemsReplenishInferred  = Expression<Int64?>("inferred_cycle_days")
let userItemsReplenishOverride  = Expression<Int64?>("user_override_cycle_days")
let userItemsNextRestockDate    = Expression<Date?>("next_restock_date")
let userItemsIsActive           = Expression<Int64>("is_active")
let userItemsIsSeasonal         = Expression<Int64?>("is_seasonal")

// MARK: - purchase_history

let purchaseHistoryTable = Table("purchase_history")
let purchaseID           = Expression<Int64>("id")
let purchaseItemID       = Expression<Int64>("item_id")
let purchaseStoreID      = Expression<Int64?>("store_id")
let purchasePrice        = Expression<Double?>("price")
let purchasedAt          = Expression<Date>("purchased_at")
let purchaseSource       = Expression<String>("source")
let purchaseQty          = Expression<Int64>("qty")

// MARK: - price_history

let priceHistoryTable = Table("price_history")
let priceHistID       = Expression<Int64>("id")
let priceHistItemID   = Expression<Int64>("item_id")
let priceHistStoreID  = Expression<Int64>("store_id")
let priceHistPrice    = Expression<Double>("price")
let priceHistDate     = Expression<Date>("observed_at")
let priceHistSource   = Expression<String>("source")

// MARK: - flyer_sales

let flyerSalesTable   = Table("flyer_sales")
let flyerID           = Expression<Int64>("id")
let flyerItemID       = Expression<Int64>("item_id")
let flyerStoreID      = Expression<Int64>("store_id")
let flyerSalePrice    = Expression<Double>("sale_price")
let flyerRegularPrice = Expression<Double?>("regular_price")
let flyerStartDate    = Expression<Date>("sale_start_date")
let flyerEndDate      = Expression<Date?>("sale_end_date")
let flyerSource       = Expression<String>("source")
let flyerFetchedAt    = Expression<Date>("fetched_at")

// MARK: - alert_log

let alertLogTable    = Table("alert_log")
let alertID          = Expression<Int64>("id")
let alertItemID      = Expression<Int64>("item_id")
let alertStoreID     = Expression<Int64>("store_id")
let alertType        = Expression<String>("alert_type")
let alertPrice       = Expression<Double>("trigger_price")
let alertFiredAt     = Expression<Date>("fired_at")
let alertSaleEventID = Expression<Int64?>("sale_event_id")
let alertNotifID     = Expression<String?>("notification_id")

// MARK: - user_stores

let userStoresTable = Table("user_stores")

// MARK: - user_settings

let userSettingsTable = Table("user_settings")
let settingKey        = Expression<String>("key")
let settingValue      = Expression<String?>("value")

// MARK: - grocery_list

// MARK: - grocery_list

let groceryListTable     = Table("grocery_list")
let groceryListID        = Expression<Int64>("id")
let groceryListItemID    = Expression<Int64>("item_id")
let groceryListPrice     = Expression<Double?>("expected_price")
let groceryListAddedAt   = Expression<Date>("added_date")
let groceryListPurchased = Expression<Int64>("is_purchased")
