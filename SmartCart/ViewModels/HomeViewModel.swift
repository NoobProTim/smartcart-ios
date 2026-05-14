// HomeViewModel.swift — SmartCart/ViewModels/HomeViewModel.swift
//
// Drives HomeView. Owns the list of tracked items and exposes:
//   • items          — all active UserItems, sorted by ReplenishmentEngine urgency
//   • todaysDeals    — items that currently have an active flyer sale
//   • restockStatus  — per-item restock badge state (from ReplenishmentEngine)
//   • isLoading      — loading spinner flag
//
// SORT ORDER (Issue #15 fix):
//   Sorting is fully delegated to ReplenishmentEngine.shared.sortedByUrgency(_:).
//   HomeViewModel no longer contains any sort or priority logic — it just passes
//   the raw array in and uses what comes back. This ensures HomeView and any
//   other consumer always see the same order.
//
// All DB reads happen on a background Task; @Published updates are
// dispatched back to the main actor automatically via @MainActor.
//
// #17 fix: Removed redundant engine.updateOnPurchase() call from markAsPurchased().
//   DatabaseManager.markPurchased() already calls recalculateReplenishment() which
//   delegates to ReplenishmentEngine — the engine was running twice per purchase.
//   Single authoritative call chain: DB write → recalculateReplenishment() → engine.

import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: - Published state

    /// All active tracked items, sorted by urgency score descending.
    /// Active-alert items pin at top, then overdue, then approaching, then ok.
    @Published var items: [UserItem] = []

    /// Items that have at least one active flyer sale today.
    /// Shown in the "Today's Deals" section at the top of HomeView.
    @Published var todaysDeals: [UserItem] = []

    /// Per-item restock status computed by ReplenishmentEngine.
    /// Key: UserItem.itemID  Value: RestockStatus
    /// HomeView reads this dictionary to decide which badge to show per row.
    @Published var restockStatuses: [Int64: RestockStatus] = [:]

    /// True while data is being fetched from the database.
    @Published var isLoading: Bool = false

    /// Total savings vs. rolling averages for the current calendar year.
    @Published var annualSavings: Double = 0

    /// Unpurchased grocery list items, shown on Home below the savings card.
    @Published var groceryList: [GroceryListItem] = []

    // MARK: - Private dependencies

    private let db     = DatabaseManager.shared
    private let engine = ReplenishmentEngine.shared

    // MARK: - Public API

    /// Loads all items and their restock statuses.
    /// Call on .onAppear and after any mutation (purchase, add item).
    func load() {
        isLoading = true
        Task {
            let allItems = db.fetchUserItems()
            let deals    = computeTodaysDeals(from: allItems)
            let statuses = computeRestockStatuses(for: allItems)

            // Delegate sort entirely to ReplenishmentEngine.
            // urgencyScore() ranks: active-alert > overdue > in-window > ok.
            // Fixes Issue #15 — items with active alerts now pin to the top.
            let sorted = engine.sortedByUrgency(allItems)

            items           = sorted
            todaysDeals     = deals
            restockStatuses = statuses
            annualSavings   = db.totalSavingsThisYear()
            groceryList     = db.fetchGroceryList()
            isLoading       = false
        }
    }

    /// Adds a new item to the user's smart list by name.
    func addItem(nameDisplay: String) {
        let nameNorm = NameNormaliser.normalise(nameDisplay)
        Task {
            let iid = db.upsertItem(nameNormalised: nameNorm, nameDisplay: nameDisplay)
            db.upsertUserItem(itemIDValue: iid)
            load()
        }
    }

    /// Records a purchase for an item.
    /// Uses DatabaseManager.markPurchased() which is atomic (Fix P0-1) and
    /// calls recalculateReplenishment() internally — ReplenishmentEngine is
    /// triggered exactly once per purchase via that DB call.
    /// Quantity defaults to 1; pass a higher value for bulk purchases
    /// (ReplenishmentEngine.updateOnPurchase will scale the restock date).
    func markAsPurchased(item: UserItem, price: Double?, quantity: Int = 1) {
        Task {
            // #17: Only one engine call path exists:
            //   markPurchased() → recalculateReplenishment() → ReplenishmentEngine
            // The previous redundant engine.updateOnPurchase() call has been removed.
            db.markPurchased(itemID: item.itemID,
                             priceAtPurchase: price,
                             quantity: quantity)
            load()
        }
    }

    // MARK: - Private helpers

    /// Asks ReplenishmentEngine for the RestockStatus of every item.
    /// Used only for badge rendering in HomeView rows — NOT for sort order.
    /// Sort order comes from sortedByUrgency(), not from these statuses.
    private func computeRestockStatuses(for items: [UserItem]) -> [Int64: RestockStatus] {
        var result: [Int64: RestockStatus] = [:]
        for item in items {
            result[item.itemID] = engine.restockStatus(for: item)
        }
        return result
    }

    /// Filters for items with at least one active flyer sale today.
    private func computeTodaysDeals(from items: [UserItem]) -> [UserItem] {
        items.filter { !db.fetchActiveSales(for: $0.itemID).isEmpty }
    }
}
