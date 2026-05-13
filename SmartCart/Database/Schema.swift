// Schema.swift
// SmartCart — Database/Schema.swift
//
// Contains two things:
//   1. Raw SQL DDL strings for all 9 tables (used by DatabaseManager.createTables())
//   2. Schema.defaultSettings — the seed rows written to user_settings on first launch
//
// UPDATED IN TASK #3 (P1-2):
// Removed daily_alert_count and daily_alert_date from defaultSettings.
// These were seeded but never incremented, creating a false second source of
// truth for the daily alert cap. The cap is now enforced exclusively by
// DatabaseManager.alertsFiredToday() which counts alert_log rows.
// See Constants.dailyAlertCap for the authoritative cap value.

import Foundation

enum Schema {

    // MARK: - Table: stores
    static let createStores = """
        CREATE TABLE IF NOT EXISTS stores (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            name            TEXT    NOT NULL UNIQUE,
            flipp_id        TEXT,
            is_selected     INTEGER NOT NULL DEFAULT 0,
            last_synced_at  TEXT
        )
    """

    // MARK: - Table: items
    static let createItems = """
        CREATE TABLE IF NOT EXISTS items (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            name_normalised   TEXT    NOT NULL UNIQUE,
            name_display      TEXT    NOT NULL,
            category          TEXT,
            unit              TEXT,
            created_at        TEXT    NOT NULL DEFAULT (datetime('now'))
        )
    """

    // MARK: - Table: user_items
    static let createUserItems = """
        CREATE TABLE IF NOT EXISTS user_items (
            id                        INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id                   INTEGER NOT NULL UNIQUE REFERENCES items(id),
            last_purchased_date       TEXT,
            last_purchased_price      REAL,
            inferred_cycle_days       INTEGER,
            user_override_cycle_days  INTEGER,
            next_restock_date         TEXT,
            has_active_alert          INTEGER NOT NULL DEFAULT 0
        )
    """

    // MARK: - Table: purchase_history
    // source must be "receipt" or "manual".
    static let createPurchaseHistory = """
        CREATE TABLE IF NOT EXISTS purchase_history (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id      INTEGER NOT NULL REFERENCES items(id),
            purchased_at TEXT    NOT NULL DEFAULT (datetime('now')),
            price        REAL,
            source       TEXT    NOT NULL DEFAULT 'receipt',
            store_id     INTEGER REFERENCES stores(id)
        )
    """

    // MARK: - Table: price_history
    // Regular shelf prices only. Sale prices belong in flyer_sales.
    static let createPriceHistory = """
        CREATE TABLE IF NOT EXISTS price_history (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id     INTEGER NOT NULL REFERENCES items(id),
            store_id    INTEGER NOT NULL REFERENCES stores(id),
            price       REAL    NOT NULL,
            observed_at TEXT    NOT NULL DEFAULT (datetime('now')),
            source      TEXT    NOT NULL DEFAULT 'flipp'
        )
    """

    // MARK: - Table: flyer_sales
    static let createFlyerSales = """
        CREATE TABLE IF NOT EXISTS flyer_sales (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id         INTEGER NOT NULL REFERENCES items(id),
            store_id        INTEGER NOT NULL REFERENCES stores(id),
            sale_price      REAL    NOT NULL,
            sale_start_date TEXT    NOT NULL,
            sale_end_date   TEXT,
            source          TEXT    NOT NULL DEFAULT 'flipp',
            fetched_at      TEXT    NOT NULL DEFAULT (datetime('now'))
        )
    """

    // Unique index prevents duplicate sale rows on daily sync.
    static let createFlyerSalesUniqueIndex = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_flyer_unique
        ON flyer_sales(item_id, store_id, sale_start_date, sale_price)
    """

    // MARK: - Table: alert_log
    // Written BEFORE calling UNUserNotificationCenter.
    static let createAlertLog = """
        CREATE TABLE IF NOT EXISTS alert_log (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id          INTEGER NOT NULL REFERENCES items(id),
            alert_type       TEXT    NOT NULL,
            trigger_price    REAL    NOT NULL,
            fired_at         TEXT    NOT NULL DEFAULT (datetime('now')),
            notification_id  TEXT
        )
    """

    // MARK: - Table: user_stores
    // ⚠️ P2-3: Not written during onboarding yet.
    static let createUserStores = """
        CREATE TABLE IF NOT EXISTS user_stores (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id   INTEGER NOT NULL UNIQUE REFERENCES stores(id),
            added_at   TEXT    NOT NULL DEFAULT (datetime('now'))
        )
    """

    // MARK: - Table: user_settings
    static let createUserSettings = """
        CREATE TABLE IF NOT EXISTS user_settings (
            key    TEXT PRIMARY KEY,
            value  TEXT NOT NULL
        )
    """

    // MARK: - Default Settings
    //
    // ⚠️ REMOVED IN TASK #3 (P1-2):
    // "daily_alert_count" and "daily_alert_date" have been removed.
    // The daily cap is now enforced ONLY by DatabaseManager.alertsFiredToday().
    // See Constants.dailyAlertCap for the cap value.
    static let defaultSettings: [String: String] = [
        "onboarding_complete":      "0",
        "notification_enabled":     "0",
        "max_daily_alerts":         String(Constants.dailyAlertCap),
        "alert_historical_low":     "1",
        "alert_sale":               "1",
        "alert_expiry":             "1",
        "user_postal_code":         "",
        "last_price_refresh":       ""
        // daily_alert_count → REMOVED (P1-2). Use alertsFiredToday() instead.
        // daily_alert_date  → REMOVED (P1-2). Use alertsFiredToday() instead.
    ]
}
