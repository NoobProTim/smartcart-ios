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
    // One row per grocery chain. isSelected drives Flipp search scope.
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
    // Canonical product catalogue. name_normalised is the dedup key.
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
    // The user's personal Smart List — one row per tracked item.
    // Replenishment data lives here: last purchase date, inferred cycle,
    // user override, next restock date.
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
    // One row per confirmed purchase event.
    // ALWAYS written via DatabaseManager.markPurchased() — never INSERT directly.
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
    // Keeping them separate lets AlertEngine distinguish a genuine price
    // drop (historical low) from a temporary sale event.
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
    // Active and historical sale/flyer events from Flipp.
    // Has a UNIQUE index (item_id, store_id, sale_start_date, sale_price)
    // so INSERT OR IGNORE prevents duplicate rows on daily sync.
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

    // Unique index that prevents duplicate sale rows on daily sync.
    // Applied in DatabaseManager.runMigrations().
    static let createFlyerSalesUniqueIndex = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_flyer_unique
        ON flyer_sales(item_id, store_id, sale_start_date, sale_price)
    """

    // MARK: - Table: alert_log
    // Written BEFORE calling UNUserNotificationCenter — this means the daily
    // cap and dedup checks work correctly even when notifications are denied.
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
    // Join between user and stores table.
    // ⚠️ P2-3: This table is currently NOT written during onboarding.
    // Store selection is tracked via user_settings keys ("store_selected_{id}").
    // Do not read from user_stores in production code until P2-3 is resolved.
    static let createUserStores = """
        CREATE TABLE IF NOT EXISTS user_stores (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id   INTEGER NOT NULL UNIQUE REFERENCES stores(id),
            added_at   TEXT    NOT NULL DEFAULT (datetime('now'))
        )
    """

    // MARK: - Table: user_settings
    // Key-value store for all user preferences and app state flags.
    static let createUserSettings = """
        CREATE TABLE IF NOT EXISTS user_settings (
            key    TEXT PRIMARY KEY,
            value  TEXT NOT NULL
        )
    """

    // MARK: - Default Settings
    // Seed rows written to user_settings on first launch.
    //
    // ⚠️ REMOVED IN TASK #3 (P1-2):
    // "daily_alert_count" and "daily_alert_date" have been removed.
    // Those fields were seeded here but never updated, creating a stale
    // second source of truth that could be misread by future code.
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
