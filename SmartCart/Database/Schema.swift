// Schema.swift — SmartCart/Database/Schema.swift
//
// Single source of truth for all SQLite table definitions.
// DO NOT edit existing CREATE TABLE strings after the app ships — add a
// migration in DatabaseManager.runMigrations() instead or you will wipe user data.
//
// Tables:
//   stores            — grocery chains the user tracks
//   items             — canonical grocery products (deduped by nameNormalised)
//   user_items        — user’s personal tracked list
//   purchase_history  — every confirmed purchase event
//   price_history     — regular shelf-price observations (NOT sale prices)
//   flyer_sales       — flyer / sale events from Flipp
//   alert_log         — every alert fired (used for daily cap + dedup)
//   user_stores       — join: user ↔ stores (see P2-3 note in UserStore.swift)
//   user_settings     — key-value config store

import Foundation

enum Schema {

    // MARK: - Table: stores
    static let createStores = """
        CREATE TABLE IF NOT EXISTS stores (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            name          TEXT    NOT NULL,
            flipp_id      TEXT,
            is_selected   INTEGER NOT NULL DEFAULT 0,
            last_synced_at TEXT
        )
        """

    // MARK: - Table: items
    static let createItems = """
        CREATE TABLE IF NOT EXISTS items (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            name_normalised  TEXT    NOT NULL UNIQUE,
            name_display     TEXT    NOT NULL,
            category         TEXT,
            unit             TEXT,
            created_at       TEXT    NOT NULL
        )
        """

    // MARK: - Table: user_items
    static let createUserItems = """
        CREATE TABLE IF NOT EXISTS user_items (
            id                        INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id                   INTEGER NOT NULL REFERENCES items(id),
            last_purchased_date       TEXT,
            last_purchased_price      REAL,
            replenishment_inferred    INTEGER,
            replenishment_override    INTEGER,
            next_restock_date         TEXT
        )
        """

    // MARK: - Table: purchase_history
    static let createPurchaseHistory = """
        CREATE TABLE IF NOT EXISTS purchase_history (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id      INTEGER NOT NULL REFERENCES items(id),
            purchased_at TEXT    NOT NULL,
            price        REAL,
            source       TEXT    NOT NULL DEFAULT 'receipt',
            store_id     INTEGER REFERENCES stores(id)
        )
        """

    // MARK: - Table: price_history
    // Regular shelf prices ONLY. Sale prices go in flyer_sales.
    static let createPriceHistory = """
        CREATE TABLE IF NOT EXISTS price_history (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id     INTEGER NOT NULL REFERENCES items(id),
            store_id    INTEGER NOT NULL REFERENCES stores(id),
            price       REAL    NOT NULL,
            observed_at TEXT    NOT NULL,
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
            fetched_at      TEXT    NOT NULL
        )
        """

    // P1-8 Fix: Unique index prevents duplicate rows on every daily sync.
    // insertFlyerSale() uses INSERT OR IGNORE against this index.
    static let createFlyerSalesUniqueIndex = """
        CREATE UNIQUE INDEX IF NOT EXISTS idx_flyer_unique
        ON flyer_sales(item_id, store_id, sale_start_date, sale_price)
        """

    // MARK: - Table: alert_log
    // Written BEFORE firing the UNNotification so daily cap works even without permission.
    static let createAlertLog = """
        CREATE TABLE IF NOT EXISTS alert_log (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id         INTEGER NOT NULL REFERENCES items(id),
            alert_type      TEXT    NOT NULL,
            trigger_price   REAL    NOT NULL,
            fired_at        TEXT    NOT NULL,
            notification_id TEXT
        )
        """

    // MARK: - Table: user_stores
    // ⚠️ P2-3: Not written during onboarding yet. See UserStore.swift note.
    static let createUserStores = """
        CREATE TABLE IF NOT EXISTS user_stores (
            id        INTEGER PRIMARY KEY,
            store_id  INTEGER NOT NULL REFERENCES stores(id),
            added_at  TEXT    NOT NULL
        )
        """

    // MARK: - Table: user_settings
    // Generic key-value store. Read/write only via DatabaseManager.getSetting / setSetting.
    static let createUserSettings = """
        CREATE TABLE IF NOT EXISTS user_settings (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        """

    // MARK: - Default settings seeded on first launch
    // Daily alert cap is enforced by counting alert_log rows where fired_at = today.
    // Do NOT track separately in user_settings — see P1-2 fix notes.
    static let defaultSettings: [(key: String, value: String)] = [
        ("onboarding_complete",   "0"),
        ("notification_enabled",  "0"),
        ("user_postal_code",      ""),
        ("last_price_refresh",    ""),
        ("app_version",           "1.0.0")
    ]

    // MARK: - All create statements in execution order
    static let allCreateStatements: [String] = [
        createStores,
        createItems,
        createUserItems,
        createPurchaseHistory,
        createPriceHistory,
        createFlyerSales,
        createFlyerSalesUniqueIndex,
        createAlertLog,
        createUserStores,
        createUserSettings
    ]
}
