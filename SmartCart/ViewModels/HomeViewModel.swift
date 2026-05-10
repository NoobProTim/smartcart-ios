// HomeViewModel.swift — SmartCart/ViewModels/HomeViewModel.swift
//
// Drives HomeView. Owns the list of tracked items and exposes:
//   • items          — all active UserItems for the Smart List
//   • todaysDeals    — items that currently have an active flyer sale
//   • restockStatus  — per-item restock badge state (from ReplenishmentEngine)
//   • isLoading      — loading spinner flag
//
// All DB reads happen on a background Task; @Published updates are
// dispatched back to the main actor automatically via @MainActor.

import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: - Published state

    /// All active tracked items, sorted: due-for-restock first, then alphabetical.
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

    // MARK: - Private dependencies

    private let db      = DatabaseManager.shared
    private let engine  = ReplenishmentEngine.shared

    // MARK: - Public API

    /// Loads all items and their restock statuses.
    /// Call on .onAppear and after any mutation (purchase, add item).
    func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let allItems   = self.db.fetchUserItems()
            let deals      = self.computeTodaysDeals(from: allItems)
            let statuses   = self.computeRestockStatuses(for: allItems)
            let sorted     = self.sortItems(allItems)

            await MainActor.run {
                self.items           = sorted
                self.todaysDeals     = deals
                self.restockStatuses = statuses
                self.isLoading       = false
            }
        }
    }

    /// Records a purchase for an item.
    /// Uses DatabaseManager.markPurchased() which is atomic (Fix P0-1).
    /// Quantity defaults to 1; pass a higher value for bulk purchases
    /// (ReplenishmentEngine will scale the restock date accordingly).
    func markAsPurchased(item: UserItem, price: Double?, quantity: Int = 1) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            self.db.markPurchased(itemID: item.itemID,
                                  priceAtPurchase: price,
                                  quantity: quantity)
            // After writing, tell ReplenishmentEngine to update the
            // next_restock_date with quantity scaling applied.
            self.engine.updateOnPurchase(itemID: item.itemID, quantity: quantity)
            await self.load()
        }
    }

    // MARK: - Private helpers

    /// Asks ReplenishmentEngine for the status of every item.
    /// This is O(n) DB reads — acceptable for typical list sizes (< 100 items).
    private func computeRestockStatuses(for items: [UserItem]) -> [Int64: RestockStatus] {
        // Pass the already-loaded UserItem directly to avoid redundant DB reads.
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

    /// Sort order: due / approaching items first (soonest restock date first),
    /// then remaining items alphabetically.
    private func sortItems(_ items: [UserItem]) -> [UserItem] {
        items.sorted { a, b in
            let statusA = engine.restockStatus(for: a)
            let statusB = engine.restockStatus(for: b)
            let priorityA = restockPriority(statusA)
            let priorityB = restockPriority(statusB)
            if priorityA != priorityB { return priorityA < priorityB }
            // Within the same priority bucket, sort by restock date (soonest first)
            // then fall back to name.
            if let da = a.nextRestockDate, let db = b.nextRestockDate {
                return da < db
            }
            return a.nameDisplay.localizedCaseInsensitiveCompare(b.nameDisplay) == .orderedAscending
        }
    }

    /// Lower number = higher in the list.
    /// TUNE: adjust these numbers to reorder priority buckets.
    private func restockPriority(_ status: RestockStatus) -> Int {
        switch status {
        case .due:                 return 0   // Always at the top
        case .approaching:         return 1   // Just below due
        case .ok:                  return 2
        case .seasonalSuppressed:  return 3   // Seasonal at the bottom
        }
    }
}
