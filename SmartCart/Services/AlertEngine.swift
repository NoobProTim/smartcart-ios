// AlertEngine.swift
// SmartCart — Services/AlertEngine.swift
//
// Evaluates all tracked items and fires push notifications for qualifying
// price events. Three alert types:
//   A — Historical Low:   today's regular price < 90-day rolling average
//   B — Sale Alert:       active flyer sale exists at a selected store
//   C — Expiry Reminder:  a qualifying sale expires within 24 hours
//
// A + B fire together as a "Combined" alert when both apply to the same item.
//
// UPDATED IN TASK #3 (P1-2):
// Removed resetDailyCounterIfNeeded() — it updated user_settings fields
// (daily_alert_count / daily_alert_date) that were never reliably read.
// The daily cap is now enforced EXCLUSIVELY by alertsFiredToday() which
// counts alert_log rows for today. This is the single source of truth.
// See Constants.dailyAlertCap and Schema.swift for context.

import Foundation
import UserNotifications

// MARK: - AlertCandidate
struct AlertCandidate {
    let itemID: Int64
    let itemName: String
    let alertType: String        // "historical_low" | "sale" | "combined" | "expiry"
    let triggerPrice: Double
    let storeName: String?
    let priority: Int            // Lower = higher priority. 1=combined, 2=historical, 3=sale, 4=expiry
}

// MARK: - AlertEngine
final class AlertEngine {

    static let shared = AlertEngine()
    private init() {}

    // MARK: - evaluate()
    func evaluate() {
        let db = DatabaseManager.shared
        guard db.getSetting(key: "notification_enabled") == "1" else { return }

        var candidates: [AlertCandidate] = []
        candidates.append(contentsOf: evaluateTypeA())
        candidates.append(contentsOf: evaluateTypeB())
        candidates.append(contentsOf: evaluateTypeC())

        let merged = mergeAndDedup(candidates)
        let sorted = merged.sorted { $0.priority < $1.priority }

        let alreadyFiredToday = db.alertsFiredToday()
        let cap = Constants.dailyAlertCap
        guard alreadyFiredToday < cap else { return }

        let remaining = cap - alreadyFiredToday
        let toFire = Array(sorted.prefix(remaining))

        for candidate in toFire {
            let notificationID = "alert-\(candidate.alertType)-\(candidate.itemID)"
            db.insertAlertLog(
                itemID: candidate.itemID,
                alertType: candidate.alertType,
                triggerPrice: candidate.triggerPrice,
                notificationID: notificationID
            )
            scheduleNotification(for: candidate, identifier: notificationID)
        }
    }

    // MARK: - evaluateTypeA()
    private func evaluateTypeA() -> [AlertCandidate] {
        let db = DatabaseManager.shared
        var candidates: [AlertCandidate] = []
        guard db.getSetting(key: "alert_historical_low") == "1" else { return [] }

        for item in db.fetchUserItems() {
            guard !db.hasAlertFiredForItem(itemID: item.itemID) else { continue }
            let avg = db.rollingAverage90(itemID: item.itemID)
            guard avg > 0 else { continue }
            guard let currentPrice = db.currentLowestPrice(for: item.itemID),
                  currentPrice > 0,
                  currentPrice < avg else { continue }
            let storeName = db.storeNameForCurrentLowestPrice(itemID: item.itemID)
            candidates.append(AlertCandidate(
                itemID: item.itemID,
                itemName: item.nameDisplay,
                alertType: "historical_low",
                triggerPrice: currentPrice,
                storeName: storeName,
                priority: 2
            ))
        }
        return candidates
    }

    // MARK: - evaluateTypeB()
    private func evaluateTypeB() -> [AlertCandidate] {
        let db = DatabaseManager.shared
        var candidates: [AlertCandidate] = []
        guard db.getSetting(key: "alert_sale") == "1" else { return [] }

        for item in db.fetchUserItems() {
            guard !db.hasAlertFiredForItem(itemID: item.itemID) else { continue }
            guard let sale = db.activeSaleForItem(itemID: item.itemID) else { continue }
            let storeName = db.fetchSelectedStores().first(where: { $0.id == sale.storeID })?.name
            candidates.append(AlertCandidate(
                itemID: item.itemID,
                itemName: item.nameDisplay,
                alertType: "sale",
                triggerPrice: sale.salePrice,
                storeName: storeName,
                priority: 3
            ))
        }
        return candidates
    }

    // MARK: - evaluateTypeC()
    private func evaluateTypeC() -> [AlertCandidate] {
        let db = DatabaseManager.shared
        var candidates: [AlertCandidate] = []
        guard db.getSetting(key: "alert_expiry") == "1" else { return [] }

        for item in db.fetchUserItems() {
            guard !db.hasAlertFiredForItem(itemID: item.itemID) else { continue }
            guard let sale = db.activeSaleForItem(itemID: item.itemID),
                  let expiresInDays = sale.expiresInDays(),
                  expiresInDays <= Constants.saleExpiryReminderDays else { continue }
            let storeName = db.fetchSelectedStores().first(where: { $0.id == sale.storeID })?.name
            candidates.append(AlertCandidate(
                itemID: item.itemID,
                itemName: item.nameDisplay,
                alertType: "expiry",
                triggerPrice: sale.salePrice,
                storeName: storeName,
                priority: 4
            ))
        }
        return candidates
    }

    // MARK: - mergeAndDedup(_:)
    private func mergeAndDedup(_ candidates: [AlertCandidate]) -> [AlertCandidate] {
        var byItem: [Int64: [AlertCandidate]] = [:]
        for candidate in candidates {
            byItem[candidate.itemID, default: []].append(candidate)
        }

        var result: [AlertCandidate] = []
        for (_, itemCandidates) in byItem {
            let hasHistoricalLow = itemCandidates.contains { $0.alertType == "historical_low" }
            let hasSale = itemCandidates.contains { $0.alertType == "sale" }

            if hasHistoricalLow && hasSale {
                let lowest = itemCandidates.min(by: { $0.triggerPrice < $1.triggerPrice })!
                result.append(AlertCandidate(
                    itemID: lowest.itemID,
                    itemName: lowest.itemName,
                    alertType: "combined",
                    triggerPrice: lowest.triggerPrice,
                    storeName: lowest.storeName,
                    priority: 1
                ))
            } else {
                if let best = itemCandidates.min(by: { $0.priority < $1.priority }) {
                    result.append(best)
                }
            }
        }
        return result
    }

    // MARK: - scheduleNotification(for:identifier:)
    private func scheduleNotification(for candidate: AlertCandidate, identifier: String) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        let price = String(format: "$%.2f", candidate.triggerPrice)
        let store = candidate.storeName ?? "your store"

        switch candidate.alertType {
        case "historical_low":
            content.title = "📉 New price low — \(candidate.itemName)"
            content.body = "\(candidate.itemName) is at a new historical low: \(price) at \(store)"
        case "sale":
            content.title = "🏷️ On sale now — \(candidate.itemName)"
            content.body = "\(candidate.itemName) is on sale at \(store) for \(price)"
        case "combined":
            content.title = "📉🏷️ Best price yet — \(candidate.itemName)"
            content.body = "\(candidate.itemName) hit a new low AND is on sale: \(price) at \(store)"
        case "expiry":
            content.title = "⏰ Sale ending soon — \(candidate.itemName)"
            content.body = "The sale on \(candidate.itemName) at \(store) expires tomorrow (\(price))"
        default:
            content.title = "Price alert — \(candidate.itemName)"
            content.body = "\(candidate.itemName): \(price)"
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[AlertEngine] Notification delivery failed for item \(candidate.itemID): \(error)")
            }
        }
    }
}
