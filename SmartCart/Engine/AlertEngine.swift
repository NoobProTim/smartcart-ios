// AlertEngine.swift — SmartCart/Engine/AlertEngine.swift
//
// Implements the 7-step daily alert evaluation loop from ATLAS Task #1-R1.
//
// Evaluation sequence:
//   Step 1  — Collect candidates (all active user_items)
//   Step 2  — Evaluate Type A (Historical Low)
//   Step 3  — Evaluate Type B (Sale Alert)
//   Step 4  — Evaluate Type C (Expiry Reminder)
//   Step 5  — Deduplication: merge A + B → combined
//   Step 6  — Priority sort: combined(1) > historical_low(2) > sale(3) > expiry(4)
//   Step 7  — Apply daily cap (max 3/day) and fire UNUserNotificationCenter requests
//
// Call AlertEngine.shared.runDailyEvaluation() from BackgroundSyncManager
// after each Flipp price fetch completes.

import Foundation
import UserNotifications

final class AlertEngine {

    static let shared = AlertEngine()
    private let db = DatabaseManager.shared
    private init() {}

    // MARK: - Entry point

    // Runs the full 7-step evaluation on a background thread.
    // Safe to call multiple times per day — dedup + daily cap prevent over-firing.
    func runDailyEvaluation() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await self.evaluate()
        }
    }

    // MARK: - Core evaluation

    private func evaluate() async {
        let notificationsEnabled = db.getSetting(key: "notification_enabled") == "1"
        guard notificationsEnabled else { return }

        // Step 1 — Collect all active user items.
        let userItems = db.fetchUserItems().filter { $0.isInRestockWindow || !restrictToRestockWindow }
        guard !userItems.isEmpty else { return }

        var candidates: [AlertCandidate] = []

        for item in userItems {
            let rollingAvg = db.rollingAverage90(for: item.itemID)
            let currentPrice = db.currentLowestPrice(for: item.itemID)
            let activeSales = db.fetchActiveSales(for: item.itemID)
            let storeID = db.primaryStoreID(for: item.itemID) ?? 0
            let storeName = db.storeName(for: storeID) ?? "Unknown Store"

            // Step 2 — Type A: Historical Low
            if let avg = rollingAvg, let price = currentPrice {
                let threshold = historicalLowThreshold
                let isLow = price <= avg * threshold
                let belowLastPurchase = item.lastPurchasedPrice.map { price <= $0 } ?? true
                let inWindow = item.isInRestockWindow
                let alreadyFired = db.hasAlertFiredForItemType(
                    itemID: item.itemID, type: .historicalLow)

                if isLow && belowLastPurchase && inWindow && !alreadyFired {
                    let monthsLow = monthsAtLow(price: price, avg: avg)
                    candidates.append(AlertCandidate(
                        itemID: item.itemID,
                        storeID: storeID,
                        type: .historicalLow,
                        price: price,
                        regularPrice: avg,
                        saleEventID: nil,
                        saleEndDate: nil,
                        itemName: item.nameDisplay,
                        storeName: storeName,
                        monthsLow: monthsLow
                    ))
                }
            }

            // Step 3 — Type B: Sale Alert
            let saleAlertsEnabled = db.getSetting(key: "sale_alerts_enabled") == "1"
            if saleAlertsEnabled {
                for sale in activeSales {
                    let discountPct = sale.discountPercent(
                        fallbackRegularPrice: rollingAvg) ?? 0
                    let meetsThreshold = discountPct >= Double(minDiscountThreshold)
                    let restockOnly = db.getSetting(key: "sale_alert_restock_only") == "1"
                    let windowOK = restockOnly ? item.isInRestockWindow : true
                    let alreadyFired = db.hasAlertFiredForSaleEvent(
                        itemID: item.itemID, saleEventID: sale.id)

                    if meetsThreshold && windowOK && !alreadyFired {
                        candidates.append(AlertCandidate(
                            itemID: item.itemID,
                            storeID: sale.storeID,
                            type: .sale,
                            price: sale.salePrice,
                            regularPrice: sale.regularPrice ?? rollingAvg,
                            saleEventID: sale.id,
                            saleEndDate: sale.validTo,
                            itemName: item.nameDisplay,
                            storeName: storeName,
                            monthsLow: nil
                        ))
                    }
                }
            }

            // Step 4 — Type C: Expiry Reminder
            let expiryEnabled = db.getSetting(key: "flyer_expiry_reminder") == "1"
            let daysBefore = Int(db.getSetting(key: "expiry_reminder_days_before") ?? "1") ?? 1
            if expiryEnabled {
                let expiringSales = db.fetchSalesExpiring(for: item.itemID, inDays: daysBefore)
                for sale in expiringSales {
                    let purchasedDuringSale = db.purchasedDuringSale(
                        itemID: item.itemID, sale: sale)
                    let alreadyFired = db.hasAlertFiredForSaleEvent(
                        itemID: item.itemID,
                        saleEventID: sale.id,
                        type: .expiry)

                    if !purchasedDuringSale && !alreadyFired {
                        candidates.append(AlertCandidate(
                            itemID: item.itemID,
                            storeID: sale.storeID,
                            type: .expiry,
                            price: sale.salePrice,
                            regularPrice: sale.regularPrice ?? rollingAvg,
                            saleEventID: sale.id,
                            saleEndDate: sale.validTo,
                            itemName: item.nameDisplay,
                            storeName: storeName,
                            monthsLow: nil
                        ))
                    }
                }
            }
        }

        // Step 5 — Merge Type A + Type B for the same item → combined
        var merged: [AlertCandidate] = []
        var itemsWithLow = Set(candidates.filter { $0.type == .historicalLow }.map { $0.itemID })
        var itemsWithSale = Set(candidates.filter { $0.type == .sale }.map { $0.itemID })
        let combinedItemIDs = itemsWithLow.intersection(itemsWithSale)

        for c in candidates {
            if combinedItemIDs.contains(c.itemID) {
                // Keep only the sale candidate and upgrade its type to combined.
                if c.type == .sale {
                    merged.append(AlertCandidate(
                        itemID: c.itemID,
                        storeID: c.storeID,
                        type: .combined,
                        price: c.price,
                        regularPrice: c.regularPrice,
                        saleEventID: c.saleEventID,
                        saleEndDate: c.saleEndDate,
                        itemName: c.itemName,
                        storeName: c.storeName,
                        monthsLow: candidates.first(where: {
                            $0.itemID == c.itemID && $0.type == .historicalLow
                        })?.monthsLow
                    ))
                }
                // Drop the historicalLow duplicate — it's merged into combined above.
            } else {
                merged.append(c)
            }
        }

        // Step 6 — Priority sort: combined(1) > historical_low(2) > sale(3) > expiry(4)
        let sorted = merged.sorted { $0.priority < $1.priority }

        // Step 7 — Enforce daily cap (max 3 alerts per day) and fire.
        let alreadyFiredToday = db.alertsFiredToday()
        let remaining = max(0, dailyAlertCap - alreadyFiredToday)
        let toFire = Array(sorted.prefix(remaining))

        for candidate in toFire {
            let notifID = UUID().uuidString
            // Write to alert_log BEFORE requesting notification delivery.
            // This ensures cap + dedup work even if notification permission is denied.
            db.logAlert(
                itemID: candidate.itemID,
                storeID: candidate.storeID,
                type: candidate.type.rawValue,
                price: candidate.price,
                saleEventID: candidate.saleEventID,
                notificationID: notifID
            )
            await fireNotification(for: candidate, id: notifID)
        }
    }

    // MARK: - Notification delivery

    private func fireNotification(for candidate: AlertCandidate, id: String) async {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch candidate.type {
        case .historicalLow:
            content.title = "Price Low — \(candidate.itemName)"
            let months = candidate.monthsLow.map { "\($0)-month" } ?? "recent"
            content.body = "🛒 \(candidate.itemName) at \(candidate.storeName) is at a \(months) low — $\(formatted(candidate.price))"

        case .sale:
            content.title = "Sale — \(candidate.itemName)"
            let wasStr = candidate.regularPrice.map { " (was $\(formatted($0)))" } ?? ""
            let endStr = candidate.saleEndDate.map { ". Sale ends \(shortDate($0))" } ?? ""
            content.body = "🏷️ \(candidate.itemName) is on sale at \(candidate.storeName) — $\(formatted(candidate.price))\(wasStr)\(endStr)"

        case .expiry:
            content.title = "Last Chance — \(candidate.itemName)"
            content.body = "⏰ \(candidate.itemName) sale at \(candidate.storeName) ends soon. $\(formatted(candidate.price))."

        case .combined:
            content.title = "Sale + Low — \(candidate.itemName)"
            let wasStr = candidate.regularPrice.map { " (was $\(formatted($0)))" } ?? ""
            let endStr = candidate.saleEndDate.map { ". Sale ends \(shortDate($0))" } ?? ""
            let months = candidate.monthsLow.map { "\($0)-month" } ?? "recent"
            content.body = "🏷️🔥 \(candidate.itemName) at \(candidate.storeName) is on sale AND at a \(months) low — $\(formatted(candidate.price))\(wasStr)\(endStr)"
        }

        // Respect quiet hours: if now is inside the quiet window, delay to quiet_hours_end.
        let trigger = quietHoursTrigger() ?? UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[AlertEngine] Failed to schedule notification \(id): \(error)")
        }
    }

    // MARK: - Helpers

    private var dailyAlertCap: Int { 3 }

    // Threshold multiplier for historical low: balanced = 0.85, aggressive = 0.90, conservative = 0.80
    private var historicalLowThreshold: Double {
        switch db.getSetting(key: "alert_sensitivity") ?? "balanced" {
        case "aggressive":   return 0.90
        case "conservative": return 0.80
        default:             return 0.85
        }
    }

    private var minDiscountThreshold: Int {
        Int(db.getSetting(key: "min_discount_threshold") ?? "0") ?? 0
    }

    private var restrictToRestockWindow: Bool {
        db.getSetting(key: "sale_alert_restock_only") == "1"
    }

    // Approximate how many months the current price is at a low vs. the 90-day avg.
    private func monthsAtLow(price: Double, avg: Double) -> Int {
        let pctBelow = (avg - price) / avg
        // Rough heuristic: each 5% below avg ≈ 1 extra month of low
        return max(1, Int(pctBelow / 0.05))
    }

    private func formatted(_ price: Double) -> String {
        String(format: "%.2f", price)
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // Returns a UNCalendarNotificationTrigger set to quiet_hours_end if
    // the current time falls inside the quiet window. Returns nil otherwise.
    private func quietHoursTrigger() -> UNNotificationTrigger? {
        let start = db.getSetting(key: "quiet_hours_start") ?? "22:00"
        let end   = db.getSetting(key: "quiet_hours_end")   ?? "08:00"
        guard let startMins = parseMins(start),
              let endMins   = parseMins(end) else { return nil }

        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMins = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        // Handles overnight window (e.g. 22:00 → 08:00)
        let inQuiet: Bool
        if startMins > endMins {
            inQuiet = nowMins >= startMins || nowMins < endMins
        } else {
            inQuiet = nowMins >= startMins && nowMins < endMins
        }
        guard inQuiet else { return nil }

        let endHour = endMins / 60
        let endMin  = endMins % 60
        var comps = DateComponents()
        comps.hour   = endHour
        comps.minute = endMin
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    private func parseMins(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }
}
