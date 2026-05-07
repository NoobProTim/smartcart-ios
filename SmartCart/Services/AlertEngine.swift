// AlertEngine.swift — SmartCart/Services/AlertEngine.swift
// Evaluates all three alert types for every tracked item and fires push notifications.
// Called daily by BackgroundSyncManager and on manual refresh.
// Priority order: Combined > Historical Low > Sale > Expiry
// Cap: max 3 alerts per day (read from Constants.dailyAlertCap)

import Foundation
import UserNotifications

struct AlertCandidate {
    let itemID: Int64
    let itemName: String
    let alertType: String   // "historical_low" | "sale" | "expiry" | "combined"
    let triggerPrice: Double
    let storeName: String?
    let saleEventID: Int64?
    let priority: Int       // Lower = higher priority (1 = Combined, 2 = Low, 3 = Sale, 4 = Expiry)
}

final class AlertEngine {
    static let shared = AlertEngine()
    private init() {}

    /// Main entry point. Evaluates all items and fires up to the daily cap.
    func evaluate() async {
        let db = DatabaseManager.shared
        guard db.alertsFiredToday() < Constants.dailyAlertCap else {
            print("[AlertEngine] Daily cap reached — skipping evaluation")
            return
        }

        let userItems = db.fetchUserItems()
        let activeSales = db.fetchActiveFlyerSales()
        var candidates: [AlertCandidate] = []

        for item in userItems {
            let lowCandidate  = evaluateTypeA(item: item)
            let saleCandidate = evaluateTypeB(item: item, sales: activeSales)

            if let low = lowCandidate, let sale = saleCandidate {
                // Both fire — merge into a single Combined alert
                candidates.append(AlertCandidate(
                    itemID: item.itemID, itemName: item.nameDisplay,
                    alertType: "combined", triggerPrice: sale.triggerPrice,
                    storeName: sale.storeName, saleEventID: sale.saleEventID, priority: 1
                ))
            } else if let low = lowCandidate {
                candidates.append(low)
            } else if let sale = saleCandidate {
                candidates.append(sale)
            }

            if let expiry = evaluateTypeC(item: item, sales: activeSales) {
                candidates.append(expiry)
            }
        }

        // Sort by priority, take up to the remaining daily cap
        let sorted = candidates.sorted { $0.priority < $1.priority }
        let remaining = Constants.dailyAlertCap - db.alertsFiredToday()
        let toFire = Array(sorted.prefix(remaining))

        for candidate in toFire {
            await fire(candidate: candidate)
        }
    }

    // ─────────────────────────────────────────────
    // MARK: - Type A: Historical Low
    // ─────────────────────────────────────────────

    private func evaluateTypeA(item: UserItem) -> AlertCandidate? {
        let db = DatabaseManager.shared
        guard item.isInRestockWindow else { return nil }
        guard let avg = db.rollingAverage90(itemID: item.itemID), avg > 0 else { return nil }
        guard let current = db.currentLowestPrice(for: item.itemID) else { return nil }
        guard current <= avg * Constants.historicalLowThreshold else { return nil }
        guard let lastPrice = item.lastPurchasedPrice, current <= lastPrice else { return nil }
        guard !db.hasAlertFiredForItem(itemID: item.itemID) else { return nil }

        return AlertCandidate(
            itemID: item.itemID, itemName: item.nameDisplay,
            alertType: "historical_low", triggerPrice: current,
            storeName: nil, saleEventID: nil, priority: 2
        )
    }

    // ─────────────────────────────────────────────
    // MARK: - Type B: Sale Alert
    // ─────────────────────────────────────────────

    private func evaluateTypeB(item: UserItem, sales: [FlyerSale]) -> AlertCandidate? {
        let db = DatabaseManager.shared
        let minDiscount = Double(db.getSetting(key: "min_discount_percent") ?? "15") ?? 15
        guard let sale = sales.first(where: { $0.itemID == item.itemID && $0.isActive }) else { return nil }
        guard let avg = db.rollingAverage90(itemID: item.itemID), avg > 0 else { return nil }
        guard let discount = sale.discountPercent(averageRegularPrice: avg), discount >= minDiscount else { return nil }
        guard !db.hasAlertFiredForItem(itemID: item.itemID) else { return nil }

        let storeName = db.fetchSelectedStores().first(where: { $0.id == sale.storeID })?.name

        return AlertCandidate(
            itemID: item.itemID, itemName: item.nameDisplay,
            alertType: "sale", triggerPrice: sale.salePrice,
            storeName: storeName, saleEventID: sale.id, priority: 3
        )
    }

    // ─────────────────────────────────────────────
    // MARK: - Type C: Expiry Reminder
    // ─────────────────────────────────────────────

    private func evaluateTypeC(item: UserItem, sales: [FlyerSale]) -> AlertCandidate? {
        let db = DatabaseManager.shared
        let reminderDays = Int(db.getSetting(key: "expiry_reminder_days") ?? "2") ?? 2
        guard let sale = sales.first(where: { $0.itemID == item.itemID && $0.isActive }) else { return nil }
        guard let daysLeft = sale.expiresInDays(), daysLeft <= reminderDays else { return nil }
        guard !db.hasAlertFiredForItem(itemID: item.itemID) else { return nil }

        let storeName = db.fetchSelectedStores().first(where: { $0.id == sale.storeID })?.name

        return AlertCandidate(
            itemID: item.itemID, itemName: item.nameDisplay,
            alertType: "expiry", triggerPrice: sale.salePrice,
            storeName: storeName, saleEventID: sale.id, priority: 4
        )
    }

    // ─────────────────────────────────────────────
    // MARK: - Fire
    // ─────────────────────────────────────────────

    private func fire(candidate: AlertCandidate) async {
        let db = DatabaseManager.shared
        let notifID = "alert-\(candidate.alertType)-\(candidate.itemID)"
        let priceStr = String(format: "$%.2f", candidate.triggerPrice)
        let storeStr = candidate.storeName ?? "your store"

        let body: String
        switch candidate.alertType {
        case "historical_low":
            body = "\(candidate.itemName) is at a new low — \(priceStr)"
        case "sale":
            body = "\(candidate.itemName) is on sale at \(storeStr) — \(priceStr)"
        case "expiry":
            body = "\(candidate.itemName) sale at \(storeStr) ends soon — \(priceStr)"
        case "combined":
            body = "\(candidate.itemName) is at a new low AND on sale at \(storeStr) — \(priceStr)"
        default:
            body = "\(candidate.itemName) — \(priceStr)"
        }

        // Write to alert_log BEFORE sending push (so cap works without notification permission)
        db.insertAlertLog(
            itemID: candidate.itemID, type: candidate.alertType,
            triggerPrice: candidate.triggerPrice,
            notificationID: notifID, saleEventID: candidate.saleEventID
        )

        let content = UNMutableNotificationContent()
        content.title = "SmartCart"
        content.body = body
        content.sound = .default
        content.badge = 1

        let request = UNNotificationRequest(
            identifier: notifID,
            content: content,
            trigger: nil  // nil = deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
