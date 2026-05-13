// ReplenishmentEngine.swift
// SmartCart — Services/ReplenishmentEngine.swift
//
// Centralises all replenishment cycle logic.
// One file owns the answer to: "When should the user restock this item?"
//
// CYCLE PRIORITY ORDER (enforced in effectiveCycleDays):
//   1. User override (set in Settings → Item Detail)
//   2. Inferred median from purchase history (requires >= Constants.inferenceMinPurchases)
//   3. Default: Constants.defaultReplenishmentDays (14 days)
//
// INFERENCE RULES (enforced in inferCycleDays):
//   - Requires >= Constants.inferenceMinPurchases (3) purchases before trusting the result.
//     Fewer purchases produce noisy gaps — e.g. a user who bought milk twice, 3 days apart,
//     would get a 3-day restock cycle forever. The threshold prevents that.
//   - Uses TRUE MEDIAN: for even-count gap arrays, averages the two middle values.
//     The old floor-division median (sorted[count/2]) biased low on even arrays.
//   - Clamps result to Constants.minReplenishmentDays...Constants.maxReplenishmentDays.
//     Prevents pathological values (< 3 days = spam; > 180 days = silent forever).
//
// URGENCY SCORE (used by HomeViewModel to sort the Smart List):
//   Higher score = shown higher in the list.
//   100+ = active alert fired for this item  (pins to very top)
//   50–99 = item is past its restock date (overdue)
//   1–49  = item is in the restock window (approaching)
//   0     = item is fine / not yet tracked

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
    // Calculates the replenishment cycle in days from purchase history.
    //
    // THRESHOLD: requires >= Constants.inferenceMinPurchases (3) purchases.
    //   Rationale: 2 purchases give exactly 1 gap — that single data point is
    //   unreliable (it could be a bulk buy, a sale coincidence, anything).
    //   3 purchases give 2 gaps; the median of 2 values is already more stable.
    //
    // TRUE MEDIAN:
    //   Odd count  → middle value (e.g. [7,14,21] → 14)
    //   Even count → average of two middle values, rounded to nearest Int
    //                (e.g. [7,14,21,28] → (14+21)/2 = 17, not 14)
    //   The old code used sorted[count/2] which always picked the lower-middle
    //   value on even arrays, biasing cycle estimates short.
    //
    // CLAMPING:
    //   Result is clamped to Constants.minReplenishmentDays...Constants.maxReplenishmentDays.
    //   Min (3 days): prevents items bought on back-to-back days triggering
    //                 daily restock notifications.
    //   Max (180 days): prevents an infrequent purchase history silencing alerts
    //                   for 6+ months.
    //
    // Returns nil if purchase count is below threshold — caller falls back to default.
    func inferCycleDays(for itemID: Int64) -> Int? {
        let dates = db.fetchPurchaseDates(itemID: itemID)

        // Threshold check — need enough data to trust the result
        guard dates.count >= Constants.inferenceMinPurchases else { return nil }

        // Build inter-purchase gaps in days (skip zero-day same-day purchases)
        var gaps: [Int] = []
        for i in 1 ..< dates.count {
            let gap = Calendar.current.dateComponents(
                [.day],
                from: dates[i - 1],
                to: dates[i]
            ).day ?? 0
            if gap > 0 { gaps.append(gap) }
        }
        guard !gaps.isEmpty else { return nil }

        // True median calculation
        let sorted = gaps.sorted()
        let count  = sorted.count
        let rawMedian: Int
        if count % 2 == 1 {
            // Odd: single middle value
            rawMedian = sorted[count / 2]
        } else {
            // Even: average the two middle values, rounded to nearest Int.
            // Add 1 before halving for correct integer rounding (avoids always flooring).
            let lower = sorted[(count / 2) - 1]
            let upper = sorted[count / 2]
            rawMedian = (lower + upper + 1) / 2
        }

        // Clamp to sensible bounds
        return min(Constants.maxReplenishmentDays, max(Constants.minReplenishmentDays, rawMedian))
    }

    // MARK: - recalculate(for:)
    // Recalculates and persists replenishment data for a single item.
    // Called after any purchase confirmation (via updateOnPurchase) or batch refresh.
    // Inference result is written to user_items.replenish_inferred so
    // effectiveCycleDays() can read it on the next call without re-scanning history.
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
    //   Numeric scores encode both the band AND how urgent within the band
    //   (e.g. 3 days overdue scores higher than 1 day overdue).
    func urgencyScore(for itemID: Int64) -> Double {
        // Band 1: active alert fired → always top
        if db.hasActiveAlert(for: itemID) { return 100.0 }

        guard let restock = nextRestockDate(for: itemID) else {
            // Never purchased — no score
            return 0.0
        }

        let now = Date()
        let daysUntilRestock = Calendar.current.dateComponents([.day], from: now, to: restock).day ?? 0

        if daysUntilRestock < 0 {
            // Band 2: overdue — the more overdue, the higher the score (capped at 50 extra points)
            let overdueScore = min(50.0, Double(-daysUntilRestock))
            return 50.0 + overdueScore
        }

        let windowDays = Double(Constants.restockWindowDays)
        if Double(daysUntilRestock) <= windowDays {
            // Band 3: in restock window — closer to restock date = higher score within 1–49
            let fraction = 1.0 - (Double(daysUntilRestock) / windowDays)
            return 1.0 + (fraction * 48.0)
        }

        return 0.0
    }

    // MARK: - restockStatus(for:)
    // Returns the RestockStatus enum for a UserItem — used by HomeView badge rendering.
    // Separate from urgencyScore because the badge needs a named state, not a number.
    func restockStatus(for item: UserItem) -> RestockStatus {
        guard let restock = item.nextRestockDate else { return .ok }
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: restock).day ?? Int.max
        if daysUntil < 0 { return .due }
        if daysUntil <= Constants.restockWindowDays { return .approaching }
        return .ok
    }

    // MARK: - sortedByUrgency(_:)
    // Returns items sorted for the Smart List display order.
    // Delegates to urgencyScore() — all sort logic lives here, not in HomeViewModel.
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
            // Tiebreak: alphabetical by display name
            return a.nameDisplay.localizedCaseInsensitiveCompare(b.nameDisplay) == .orderedAscending
        }
    }

    // MARK: - updateOnPurchase(itemID:quantity:)
    // Called by DatabaseManager.recalculateReplenishment() after every purchase write.
    // Recalculates cycle days and next restock date for the item.
    // quantity parameter reserved for P2-4 quantity-scaling (do not implement now).
    func updateOnPurchase(itemID: Int64, quantity: Int) {
        // TODO P2-4: scale restock date by quantity (e.g. buying 2 units doubles the cycle)
        recalculate(for: itemID)
    }
}
