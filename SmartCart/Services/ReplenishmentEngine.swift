// ReplenishmentEngine.swift
// SmartCart — Services/ReplenishmentEngine.swift
//
// NEW FILE — Task #3, Module E.
//
// Centralises all replenishment cycle logic that was previously scattered
// across DatabaseManager in ad-hoc functions. One file owns the answer to:
// "When should the user restock this item?"
//
// WHY CENTRALISE:
// DatabaseManager is responsible for persistence — not business logic.
// Having replenishment calculations inline in DatabaseManager made them
// hard to test in isolation and easy to accidentally skip.
// ReplenishmentEngine is a pure logic layer: it reads from DatabaseManager,
// computes dates and windows, and writes back to user_items.
//
// CYCLE PRIORITY ORDER (enforced in effectiveCycleDays):
//   1. User override (set in Settings → Item Detail)
//   2. Inferred median from purchase history (requires >= 2 purchases)
//   3. Default: Constants.defaultReplenishmentDays (14 days)

import Foundation

final class ReplenishmentEngine {

    static let shared = ReplenishmentEngine()
    private init() {}

    private var db: DatabaseManager { DatabaseManager.shared }

    // MARK: - effectiveCycleDays(for:)
    // Priority: user override → inferred median → default (14 days)
    func effectiveCycleDays(for itemID: Int64) -> Int {
        guard let userItem = db.fetchUserItem(itemID: itemID) else {
            return Constants.defaultReplenishmentDays
        }
        if let override = userItem.userOverrideCycleDays, override > 0 {
            return override
        }
        if let inferred = userItem.inferredCycleDays, inferred > 0 {
            return inferred
        }
        return Constants.defaultReplenishmentDays
    }

    // MARK: - nextRestockDate(for:)
    // Formula: nextRestockDate = lastPurchasedDate + effectiveCycleDays
    // Returns nil when the item has never been purchased.
    func nextRestockDate(for itemID: Int64) -> Date? {
        guard let userItem = db.fetchUserItem(itemID: itemID),
              let lastPurchased = userItem.lastPurchasedDate else {
            return nil
        }
        let cycleDays = effectiveCycleDays(for: itemID)
        return Calendar.current.date(byAdding: .day, value: cycleDays, to: lastPurchased)
    }

    // MARK: - isInRestockWindow(for:)
    // Returns true when nextRestockDate is within Constants.restockWindowDays.
    // Returns false when nextRestockDate is nil (never purchased).
    func isInRestockWindow(for itemID: Int64) -> Bool {
        guard let restock = nextRestockDate(for: itemID) else { return false }
        let daysUntilRestock = Calendar.current.dateComponents([.day], from: Date(), to: restock).day ?? Int.max
        return daysUntilRestock <= Constants.restockWindowDays
    }

    // MARK: - inferCycleDays(for:)
    // Calculates the median gap (in days) between consecutive purchases.
    // Requires >= 2 purchase_history rows. Returns nil with fewer.
    //
    // TODO P2-1: Use true median for even-count datasets.
    // Current: sorted[count / 2] → lower-middle value for even arrays.
    func inferCycleDays(for itemID: Int64) -> Int? {
        let purchases = db.fetchPurchaseHistory(itemID: itemID)
            .sorted { $0.purchasedAt < $1.purchasedAt }
        guard purchases.count >= 2 else { return nil }

        var gaps: [Int] = []
        for i in 1..<purchases.count {
            let gap = Calendar.current.dateComponents(
                [.day],
                from: purchases[i - 1].purchasedAt,
                to: purchases[i].purchasedAt
            ).day ?? 0
            if gap > 0 { gaps.append(gap) }
        }
        guard !gaps.isEmpty else { return nil }

        // TODO P2-1: true median for even-count datasets
        let sorted = gaps.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - recalculate(for:)
    // Recalculates and persists replenishment data for a single item.
    // Called after any purchase confirmation.
    func recalculate(for itemID: Int64) {
        let inferred = inferCycleDays(for: itemID)
        let restock = nextRestockDate(for: itemID)
        db.updateReplenishmentData(
            itemID: itemID,
            inferredCycleDays: inferred,
            nextRestockDate: restock
        )
    }

    // MARK: - recalculateAll()
    // Recalculates replenishment data for ALL tracked items.
    // Called after batch receipt import or app launch / background refresh.
    func recalculateAll() {
        let allItems = db.fetchUserItems()
        for item in allItems {
            recalculate(for: item.itemID)
        }
        print("[ReplenishmentEngine] recalculateAll() complete — \(allItems.count) items updated")
    }

    // MARK: - sortedByUrgency(_:)
    // Returns items sorted for the Smart List display order.
    // Sort order:
    //   1. Items in restock window (ascending by days until restock)
    //   2. Items with active alerts
    //   3. All other items (alphabetical)
    func sortedByUrgency(_ items: [UserItem]) -> [UserItem] {
        return items.sorted { a, b in
            let aInWindow = isInRestockWindow(for: a.itemID)
            let bInWindow = isInRestockWindow(for: b.itemID)
            if aInWindow != bInWindow { return aInWindow }
            if aInWindow && bInWindow {
                let aDate = nextRestockDate(for: a.itemID) ?? Date.distantFuture
                let bDate = nextRestockDate(for: b.itemID) ?? Date.distantFuture
                if aDate != bDate { return aDate < bDate }
            }
            if a.hasActiveAlert != b.hasActiveAlert { return a.hasActiveAlert }
            return a.nameDisplay.localizedCaseInsensitiveCompare(b.nameDisplay) == .orderedAscending
        }
    }
}
