// ReplenishmentEngine.swift — SmartCart/Engine/ReplenishmentEngine.swift
//
// THE REPLENISHMENT BRAIN
// -----------------------
// This engine answers one question: "Is this item running low, and when
// should the user restock it?"
//
// It is the single source of truth for restock logic. AlertEngine,
// HomeViewModel, and ItemDetailView all delegate here — no duplicated math.
//
// ──────────────────────────────────────────────────────────────
// HOW IT WORKS (plain English for Timothy)
// ──────────────────────────────────────────────────────────────
// 1. Every item has an "effective cycle" — how many days between purchases.
//    This comes from the user override first, then the inferred average.
// 2. "Restock window" opens when today >= last_purchase + (cycle × 0.5).
//    Example: milk bought every 14 days → window opens on day 7.
// 3. "Approaching" (amber badge) = within `approachingWindowDays` of the
//    window opening — gives a heads-up before the item is actually due.
// 4. "Due" (red badge) = inside the restock window right now.
// 5. Seasonal items get a special suppressed status — no nudges at all
//    because their purchase pattern is too irregular to predict reliably.
//
// TUNABLE CONSTANTS (look for "TUNE:" comments below)
// ──────────────────────────────────────────────────────────────

import Foundation

/// The four states a UserItem can be in from a replenishment perspective.
/// Used by HomeViewModel to drive badge colours in the Smart List.
enum RestockStatus {
    /// Plenty of time left — no badge shown.
    case ok
    /// Getting close to the restock window — show an amber "Restock soon" pill.
    case approaching
    /// Inside the restock window — show a red "Due" pill.
    case due
    /// Item is seasonal; restock nudges are suppressed entirely.
    case seasonalSuppressed
}

final class ReplenishmentEngine {

    // Shared singleton — matches the pattern used by AlertEngine and DatabaseManager.
    static let shared = ReplenishmentEngine()

    private let db = DatabaseManager.shared
    private init() {}

    // ──────────────────────────────────────────────────────────────
    // TUNABLE CONSTANTS
    // Change these numbers to adjust how early "Restock soon" appears.
    // ──────────────────────────────────────────────────────────────

    /// Days before the restock window opens that "approaching" kicks in.
    /// Default 3 — i.e., if the window opens in 3 days or fewer, show amber.
    /// TUNE: raise to 5 for earlier warnings; lower to 1 for tighter alerts.
    private let approachingWindowDays: Int = 3

    /// Minimum valid cycle length in days. Cycles shorter than this are
    /// considered data noise and ignored.
    /// TUNE: lower to 1 if you want to track daily-purchase items.
    private let minimumValidCycleDays: Int = 2

    // ──────────────────────────────────────────────────────────────
    // PUBLIC API
    // These are the three methods the rest of the app calls.
    // ──────────────────────────────────────────────────────────────

    /// Call this immediately after recording a purchase.
    /// It recalculates the predicted restock date, scaling forward by
    /// `quantity` cycles so a bulk buy doesn't trigger an instant nudge.
    ///
    /// Example: if the cycle is 14 days and the user bought 3 units,
    /// the next restock date is pushed 42 days out.
    ///
    /// - Parameters:
    ///   - itemID: The item that was purchased.
    ///   - quantity: How many units were bought (minimum 1).
    func updateOnPurchase(itemID: Int64, quantity: Int) {
        // DatabaseManager+Fixes already writes purchase_history and
        // recalculates the base cycle. We re-read the cycle here and
        // apply the quantity scale on top.
        guard let item = db.fetchUserItem(itemID: itemID) else { return }
        guard let cycle = validCycle(from: item) else { return }

        // Scale: buying 2 units pushes the window out 2× the normal cycle.
        let scaledDays = cycle * max(1, quantity)
        let nextRestock = Calendar.current.date(
            byAdding: .day, value: scaledDays, to: Date()
        )
        db.setNextRestockDate(itemID: itemID, date: nextRestock)
    }

    /// Returns the predicted date the user will need to restock this item.
    /// Returns nil if there is not enough data to make a prediction
    /// (e.g. never purchased, or cycle data is missing/bogus).
    ///
    /// - Parameter itemID: The item to predict for.
    func predictedRestockDate(for itemID: Int64) -> Date? {
        guard let item = db.fetchUserItem(itemID: itemID) else { return nil }
        // Use the stored next_restock_date if it's already been calculated.
        if let stored = item.nextRestockDate { return stored }
        // Fall back to computing on the fly from last purchase + cycle.
        guard let last  = item.lastPurchasedDate,
              let cycle = validCycle(from: item) else { return nil }
        return Calendar.current.date(byAdding: .day, value: cycle, to: last)
    }

    /// Returns true when the item is inside its restock window right now.
    /// This is the canonical check — AlertEngine delegates here instead of
    /// computing its own `isInRestockWindow` logic.
    ///
    /// Seasonal items always return false (suppress restock nudges).
    ///
    /// - Parameters:
    ///   - itemID: The item to check.
    ///   - date: The date to evaluate against (defaults to today).
    func isInRestockWindow(itemID: Int64, asOf date: Date = Date()) -> Bool {
        guard let item = db.fetchUserItem(itemID: itemID) else { return false }
        guard !item.isSeasonal else { return false }   // Seasonal → suppress
        return windowIsOpen(for: item, asOf: date)
    }

    /// Returns the restock status for use in the Smart List UI.
    /// This is what HomeViewModel calls for every item to decide which badge to show.
    ///
    /// - Parameters:
    ///   - item: A fully loaded UserItem (from db.fetchUserItems()).
    ///   - date: The date to evaluate against (defaults to today).
    func restockStatus(for item: UserItem, asOf date: Date = Date()) -> RestockStatus {
        // Seasonal items: suppress everything.
        if item.isSeasonal { return .seasonalSuppressed }

        // No cycle data → can't predict → no badge.
        guard let cycle = validCycle(from: item),
              let last  = item.lastPurchasedDate else { return .ok }

        // Window open date: last_purchased + (cycle × 0.5)
        // TUNE: change 0.5 to a different fraction to open the window earlier/later.
        let halfCycle   = Double(cycle) * 0.5
        let windowOpen  = last.addingTimeInterval(halfCycle * 86_400)

        // Due: today is on or after the window opening.
        if date >= windowOpen { return .due }

        // Approaching: window opens within `approachingWindowDays` days.
        let daysUntilWindow = Calendar.current.dateComponents(
            [.day], from: date, to: windowOpen
        ).day ?? Int.max
        if daysUntilWindow <= approachingWindowDays { return .approaching }

        return .ok
    }

    // ──────────────────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ──────────────────────────────────────────────────────────────

    /// Returns the effective cycle (user override preferred over inferred),
    /// or nil if the cycle is missing, zero, or negative (bogus data guard).
    private func validCycle(from item: UserItem) -> Int? {
        guard let cycle = item.effectiveCycleDays,
              cycle >= minimumValidCycleDays else { return nil }
        return cycle
    }

    /// True when today is at or past the half-cycle window opening date.
    private func windowIsOpen(for item: UserItem, asOf date: Date) -> Bool {
        guard let last  = item.lastPurchasedDate,
              let cycle = validCycle(from: item) else { return false }
        let halfCycle  = Double(cycle) * 0.5
        let windowOpen = last.addingTimeInterval(halfCycle * 86_400)
        return date >= windowOpen
    }
}
