// AlertEngine.swift — SmartCart/Services/AlertEngine.swift
// P1B fixes applied:
//   P1-A: weekly cap wired — both alertsFiredToday() and alertsFiredThisWeek() gate firing
//   P1-E: seasonal items skipped before any price/history work
//   P1-F: store-scoped rollingAverage90(for:storeID:) used for threshold; all-stores fallback retained
// Part 7 fix:
//   db.storeName(for:) → db.fetchStoreName(for:) matching rename in DatabaseManager+Alerts.swift
import Foundation
import UserNotifications

final class AlertEngine {

    static let shared = AlertEngine()
    private let db = DatabaseManager.shared
    private init() {}

    // MARK: - Entry point
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

        // P1-A: Gate on BOTH daily and weekly caps before entering the item loop.
        let firedToday  = db.alertsFiredToday()
        let firedWeek   = db.alertsFiredThisWeek()
        let remToday    = max(0, Constants.maxAlertsPerDay  - firedToday)
        let remWeek     = max(0, Constants.maxAlertsPerWeek - firedWeek)
        let globalRem   = min(remToday, remWeek)
        guard globalRem > 0 else { return }

        let minDiscount = Int(db.getSetting(key: "min_discount_threshold") ?? "0") ?? 0
        let restockOnly = db.getSetting(key: "sale_alert_restock_only") == "1"

        let userItems = db.fetchUserItems()
        guard !userItems.isEmpty else { return }

        var candidates: [AlertCandidate] = []

        for item in userItems {
            // P1-E: Skip seasonal items before any expensive price/history work.
            if item.isSeasonal { continue }

            // P1-F: Resolve primary store; use store-scoped average for threshold.
            let storeID   = db.primaryStoreID(for: item.itemID) ?? 0
            // Fix: was db.storeName(for:) — renamed to db.fetchStoreName(for:)
            let storeName = db.fetchStoreName(for: storeID) ?? "Unknown Store"

            // P1-F: Prefer store-scoped 90-day average; fall back to all-stores if no store data.
            let rollingAvg: Double?
            if storeID > 0 {
                rollingAvg = db.rollingAverage90(for: item.itemID, storeID: storeID)
                          ?? db.rollingAverage90(for: item.itemID)
            } else {
                rollingAvg = db.rollingAverage90(for: item.itemID)
            }

            let currentPrice = db.currentLowestPrice(for: item.itemID)
            let activeSales  = db.fetchActiveSales(for: item.itemID)

            // Type A: Historical Low
            if let avg = rollingAvg, let price = currentPrice {
                let threshold        = historicalLowThreshold
                let isLow            = price <= avg * threshold
                let belowLastPurchase = item.lastPurchasedPrice.map { price <= $0 } ?? true
                let inWindow         = item.isInRestockWindow
                let alreadyFired     = db.hasAlertFiredForItemType(itemID: item.itemID, type: .historicalLow)

                if isLow && belowLastPurchase && inWindow && !alreadyFired {
                    candidates.append(AlertCandidate(
                        itemID: item.itemID, storeID: storeID, type: .historicalLow,
                        price: price, regularPrice: avg, saleEventID: nil, saleEndDate: nil,
                        itemName: item.nameDisplay, storeName: storeName,
                        monthsLow: monthsAtLow(price: price, avg: avg)
                    ))
                }
            }

            // Type B: Sale Alert
            let saleAlertsEnabled = db.getSetting(key: "sale_alerts_enabled") == "1"
            if saleAlertsEnabled {
                for sale in activeSales {
                    let discountPct  = sale.discountPercent(fallbackRegularPrice: rollingAvg) ?? 0
                    let windowOK     = restockOnly ? item.isInRestockWindow : true
                    let alreadyFired = db.hasAlertFiredForSaleEvent(itemID: item.itemID, saleEventID: sale.id)

                    if discountPct >= Double(minDiscount) && windowOK && !alreadyFired {
                        candidates.append(AlertCandidate(
                            itemID: item.itemID, storeID: sale.storeID, type: .sale,
                            price: sale.salePrice, regularPrice: sale.regularPrice ?? rollingAvg,
                            saleEventID: sale.id, saleEndDate: sale.validTo,
                            itemName: item.nameDisplay, storeName: storeName, monthsLow: nil
                        ))
                    }
                }
            }

            // Type C: Expiry Reminder
            let expiryEnabled = db.getSetting(key: "flyer_expiry_reminder") == "1"
            let daysBefore    = Int(db.getSetting(key: "expiry_reminder_days_before") ?? "1") ?? 1
            if expiryEnabled {
                for sale in db.fetchSalesExpiring(for: item.itemID, inDays: daysBefore) {
                    let purchased    = db.purchasedDuringSale(itemID: item.itemID, sale: sale)
                    let alreadyFired = db.hasAlertFiredForSaleEvent(itemID: item.itemID,
                                                                    saleEventID: sale.id,
                                                                    type: .expiry)
                    if !purchased && !alreadyFired {
                        candidates.append(AlertCandidate(
                            itemID: item.itemID, storeID: sale.storeID, type: .expiry,
                            price: sale.salePrice, regularPrice: sale.regularPrice ?? rollingAvg,
                            saleEventID: sale.id, saleEndDate: sale.validTo,
                            itemName: item.nameDisplay, storeName: storeName, monthsLow: nil
                        ))
                    }
                }
            }
        }

        // Merge Type A + B → combined where same item has both
        var merged: [AlertCandidate] = []
        let itemsWithLow  = Set(candidates.filter { $0.type == .historicalLow }.map { $0.itemID })
        let itemsWithSale = Set(candidates.filter { $0.type == .sale }.map { $0.itemID })
        let combinedIDs   = itemsWithLow.intersection(itemsWithSale)

        for c in candidates {
            if combinedIDs.contains(c.itemID) {
                if c.type == .sale {
                    merged.append(AlertCandidate(
                        itemID: c.itemID, storeID: c.storeID, type: .combined,
                        price: c.price, regularPrice: c.regularPrice,
                        saleEventID: c.saleEventID, saleEndDate: c.saleEndDate,
                        itemName: c.itemName, storeName: c.storeName,
                        monthsLow: candidates.first(where: {
                            $0.itemID == c.itemID && $0.type == .historicalLow
                        })?.monthsLow
                    ))
                }
                // Drop the raw .historicalLow entry — it's merged into .combined above.
            } else {
                merged.append(c)
            }
        }

        let sorted = merged.sorted { $0.priority < $1.priority }

        // P1-A: Respect the smaller of the two remaining caps.
        let toFire = Array(sorted.prefix(globalRem))

        for candidate in toFire {
            let notifID = UUID().uuidString
            db.logAlert(
                itemID: candidate.itemID, storeID: candidate.storeID,
                type: candidate.type.rawValue, price: candidate.price,
                saleEventID: candidate.saleEventID, notificationID: notifID
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
            content.body  = "🛒 \(candidate.itemName) at \(candidate.storeName) is at a \(months) low — $\(formatted(candidate.price))"
        case .sale:
            content.title = "Sale — \(candidate.itemName)"
            let wasStr = candidate.regularPrice.map { " (was $\(formatted($0)))" } ?? ""
            let endStr = candidate.saleEndDate.map { ". Sale ends \(shortDate($0))" } ?? ""
            content.body  = "🏷️ \(candidate.itemName) is on sale at \(candidate.storeName) — $\(formatted(candidate.price))\(wasStr)\(endStr)"
        case .expiry:
            content.title = "Last Chance — \(candidate.itemName)"
            content.body  = "⏰ \(candidate.itemName) sale at \(candidate.storeName) ends soon. $\(formatted(candidate.price))."
        case .combined:
            content.title = "Sale + Low — \(candidate.itemName)"
            let wasStr = candidate.regularPrice.map { " (was $\(formatted($0)))" } ?? ""
            let endStr = candidate.saleEndDate.map { ". Sale ends \(shortDate($0))" } ?? ""
            let months = candidate.monthsLow.map { "\($0)-month" } ?? "recent"
            content.body  = "🏷️🔥 \(candidate.itemName) at \(candidate.storeName) is on sale AND at a \(months) low — $\(formatted(candidate.price))\(wasStr)\(endStr)"
        }

        let trigger = quietHoursTrigger() ?? UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[AlertEngine] Failed to schedule notification \(id): \(error)")
        }
    }

    // MARK: - Helpers
    private var historicalLowThreshold: Double {
        switch db.getSetting(key: "alert_sensitivity") ?? "balanced" {
        case "aggressive":   return 0.90
        case "conservative": return 0.80
        default:             return 0.85
        }
    }

    private func monthsAtLow(price: Double, avg: Double) -> Int {
        let pctBelow = (avg - price) / avg
        return max(1, Int(pctBelow / 0.05))
    }

    private func formatted(_ price: Double) -> String { String(format: "%.2f", price) }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }

    private func quietHoursTrigger() -> UNNotificationTrigger? {
        let start = db.getSetting(key: "quiet_hours_start") ?? "22:00"
        let end   = db.getSetting(key: "quiet_hours_end")   ?? "08:00"
        guard let startMins = parseMins(start), let endMins = parseMins(end) else { return nil }
        let now     = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMins = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let inQuiet: Bool
        if startMins > endMins { inQuiet = nowMins >= startMins || nowMins < endMins }
        else                   { inQuiet = nowMins >= startMins && nowMins < endMins }
        guard inQuiet else { return nil }
        var comps = DateComponents()
        comps.hour = endMins / 60; comps.minute = endMins % 60
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    private func parseMins(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }
}
