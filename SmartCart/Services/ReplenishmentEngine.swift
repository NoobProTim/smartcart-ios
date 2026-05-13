// ReplenishmentEngine.swift
// SmartCart — Services/ReplenishmentEngine.swift
//
// Centralises all replenishment cycle logic.
// One file owns the answer to: "When should the user restock this item?"
//
// CYCLE PRIORITY ORDER (enforced in effectiveCycleDays):
//   1. User override (set in Settings → Item Detail)
//   2. Inferred median from purchase history (requires >= 3 purchases — Task #4 Part 3)
//   3. Default: Constants.defaultReplenishmentDays (14 days)
//
// URGENCY SCORE (used by HomeViewModel to sort the Smart List):
//   Higher score = shown higher in the list.
//   100+ = active alert fired for this item  (pins to very top)
//   50–99 = item is past its restock date (overdue)
//   1–49  = item is in the restock window (approaching)
//   0     = item is fine / not yet tracked
//
// WHY SEPARATE urgencyScore FROM sortedByUrgency:
//   urgencyScore() gives HomeViewModel a stable numeric sort key so the
//   sort closure is a one-liner. sortedByUrgency() is a convenience wrapper
//   for callers that just want a sorted array without caring about scores.

import Foundation

final class ReplenishmentEngine {

    static let shared = ReplenishmentEngine()
    private init() {}

    private var db: DatabaseManager { DatabaseManager.shared }

    // MARK: - effectiveCycleDays(for:)
    // Returns the number of days between restocks for this item.
    // Priority: user override → inferred median → default (14 days).
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
    // Formula: nextRestockDate = lastPurchasedDate + effectiveCycleDays.
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
    // NOTE: true median + threshold raise + clamping resolved in Task #4 Part 3.
    //
    // TODO P2-1: Use true median for even-count datasets. ← resolved in Part 3
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

        // TODO P2-1: true median for even-count datasets — resolved in Part 3
        let sorted = gaps.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - recalculate(for:)
    // Recalculates and persists replenishment data for a single item.
    // Called after any purchase confirmation.
    func recalculate(for itemID: Int64) {
        let inferred = inferCycleDays(for: itemID)
        let restock  = nextRestockDate(for: itemID)
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

    // MARK: - urgencyScore(for:)
    // Returns a numeric urgency score for a single item.
    // Higher score = item should appear higher in the Smart List.
    //
    // Score bands:
    //   100+ → item has an active fired alert (pins to very top)
    //   50–99 → item is overdue for restock (past nextRestockDate)
    //   1–49  → item is in the restock window (within Constants.restockWindowDays)
    //   0     → item is fine or has never been purchased
    //
    // WHY NUMERIC SCORE:
    //   A simple enum sort loses the tiebreaker within each band.
    //   Numeric scores let us encode both the band AND how urgent
    //   within the band (e.g. 3 days overdue scores higher than 1 day overdue).
    func urgencyScore(for itemID: Int64) -> Double {
        // Band 1: active alert fires → always top
        let hasAlert = db.hasActiveAlert(for: itemID)
        if hasAlert { return 100.0 }

        guard let restock = nextRestockDate(for: itemID) else {
            // Never purchased — no score
            return 0.0
        }

        let now = Date()
        let daysUntilRestock = Calendar.current.dateComponents([.day], from: now, to: restock).day ?? 0

        if daysUntilRestock < 0 {
            // Band 2: overdue — the more overdue, the higher the score
            // Cap at 50 extra points (99 total max in this band)
            let overdueScore = min(50.0, Double(-daysUntilRestock))
            return 50.0 + overdueScore
        }

        let windowDays = Double(Constants.restockWindowDays)
        if Double(daysUntilRestock) <= windowDays {
            // Band 3: in window — closer to restock = higher score within 1–49
            // Items with 0 days left score 49; items at windowDays score ~1
            let fraction = 1.0 - (Double(daysUntilRestock) / windowDays)
            return 1.0 + (fraction * 48.0)
        }

        return 0.0
    }

    // MARK: - restockStatus(for:)
    // Returns the RestockStatus enum for a UserItem — used by HomeView badge rendering.
    // This is separate from urgencyScore because the badge needs a named state,
    // not a number.
    func restockStatus(for item: UserItem) -> RestockStatus {
        guard let restock = item.nextRestockDate else { return .ok }
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: restock).day ?? Int.max
        if daysUntil < 0 { return .due }
        if daysUntil <= Constants.restockWindowDays { return .approaching }
        return .ok
    }

    // MARK: - sortedByUrgency(_:)
    // Returns items sorted for the Smart List display order.
    // Delegates to urgencyScore() so all sort logic lives here, not in HomeViewModel.
    //
    // Sort order (highest urgencyScore first):
    //   1. Items with active alerts   (score ≥ 100)
    //   2. Overdue items              (score 50–99)
    //   3. Items in restock window    (score 1–49)
    //   4. All other items            (score 0, alphabetical tiebreak)
    func sortedByUrgency(_ items: [UserItem]) -> [UserItem] {
        return items.sorted { a, b in
            let scoreA = urgencyScore(for: a.itemID)
            let scoreB = urgencyScore(for: b.itemID)
            if scoreA != scoreB { return scoreA > scoreB }
            // Tiebreak: alphabetical
            return a.nameDisplay.localizedCaseInsensitiveCompare(b.nameDisplay) == .orderedAscending
        }
    }

    // MARK: - updateOnPurchase(itemID:quantity:)
    // Called by HomeViewModel after a purchase is recorded.
    // Recalculates cycle days and next restock date for the item.
    // The quantity parameter is reserved for future quantity-scaling logic (P2-4).
    func updateOnPurchase(itemID: Int64, quantity: Int) {
        // TODO P2-4: scale restock date by quantity (e.g. buying 2 units doubles the cycle)
        recalculate(for: itemID)
    }
}
