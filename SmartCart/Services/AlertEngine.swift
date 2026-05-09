// AlertEngine.swift — SmartCart/Services/AlertEngine.swift
//
// Decides whether to fire a push notification for each user item.
// Called by BackgroundSyncManager after every price fetch completes.
//
// Alert logic (per item):
//   1. Fetch current lowest price from price_history.
//   2. Fetch the all-time historical low.
//   3. If current ≤ historical low AND item is in restock window → FIRE historical_low alert.
//   4. Check daily cap (Constants.maxAlertsPerDay) across all items.
//   5. P1-5: Check per-item cap — only one alert per item per day.
//   6. Write alert_log row BEFORE scheduling notification.
//   7. Schedule UNUserNotificationCenter request.
//
// Thresholds (from Constants):
//   historicalLowThreshold: price must be ≤ 85% of 90-day rolling average to count as low

import Foundation
import UserNotifications

final class AlertEngine {

    static let shared = AlertEngine()
    private init() {}

    // MARK: - Main evaluation loop

    // Evaluates every user item and fires alerts where conditions are met.
    // Call after FlippService.fetchPrices() completes.
    func evaluateAlerts() async {
        let items = DatabaseManager.shared.fetchUserItems()

        for item in items {
            guard DatabaseManager.shared.alertsFiredToday() < Constants.maxAlertsPerDay else {
                print("[AlertEngine] Daily cap reached. Stopping.")
                return
            }

            // P1-5: Skip this item if an alert already fired for it today.
            guard !DatabaseManager.shared.hasAlertFiredForItem(itemID: item.itemID) else {
                continue
            }

            guard let currentPrice = DatabaseManager.shared.currentLowestPrice(for: item.itemID),
                  let historicalLow = DatabaseManager.shared.historicalLow(itemID: item.itemID)
            else { continue }

            // Fire when current price matches or beats the all-time historical low.
            guard currentPrice <= historicalLow else { continue }

            // Optionally gated on restock window (items due for replenishment only).
            // To alert on ALL lows regardless of restock, remove this guard.
            let userItem = buildUserItem(from: item)
            guard userItem.isInRestockWindow else { continue }

            await fireAlert(itemID: item.itemID,
                            itemName: item.nameDisplay,
                            triggerPrice: currentPrice,
                            alertType: "historical_low")
        }
    }

    // MARK: - Fire a single alert

    // Writes to alert_log FIRST, then schedules the notification.
    // If notification permission is denied the log row still exists —
    // this keeps hasAlertFiredForItem() accurate.
    private func fireAlert(itemID: Int64, itemName: String,
                           triggerPrice: Double, alertType: String) async {
        let notifID = "alert-\(alertType)-\(itemID)"

        // Write the log row before the notification attempt.
        DatabaseManager.shared.logAlert(itemID: itemID,
                                        alertType: alertType,
                                        triggerPrice: triggerPrice,
                                        notificationID: notifID)

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(itemName) is at an all-time low"
        content.body  = String(format: "Now $%.2f — a great time to stock up.", triggerPrice)
        content.sound = .default

        // Deliver immediately.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: notifID,
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Helpers

    // Converts a UserItemRow (DB row) into a UserItem model for isInRestockWindow check.
    private func buildUserItem(from row: DatabaseManager.UserItemRow) -> UserItem {
        UserItem(
            id: 0, // Not used for logic
            itemID: row.itemID,
            nameDisplay: row.nameDisplay,
            lastPurchasedDate: row.lastPurchasedDate.flatMap { DateHelper.date(from: $0) },
            lastPurchasedPrice: row.lastPurchasedPrice,
            inferredCycleDays: row.replenishmentInferred.map { Int($0) },
            userOverrideCycleDays: row.replenishmentOverride.map { Int($0) },
            nextRestockDate: row.nextRestockDate.flatMap { DateHelper.date(from: $0) },
            hasActiveAlert: false // Not needed here
        )
    }
}
