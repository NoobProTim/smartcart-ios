// AlertEngine.swift — SmartCart/Services/AlertEngine.swift
//
// Decides whether to fire a push notification for each user item.
// Called by BackgroundSyncManager after every price fetch completes.
//
// Alert logic (per item):
//   1. Read user settings: min_discount_threshold, sale_alert_restock_only, quiet_hours_start/end.
//   2. Fetch current lowest price from price_history.
//   3. Fetch the all-time historical low.
//   4. Gate on restock window only when sale_alert_restock_only == "1".
//   5. Gate on min discount threshold.
//   6. Check daily cap (Constants.maxAlertsPerDay) across all items.
//   7. Check per-item cap — only one alert per item per day.
//   8. Write alert_log row BEFORE scheduling notification.
//   9. Schedule UNUserNotificationCenter request (respecting quiet hours).
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

        // P0-A: Read both user settings ONCE before the loop.
        let minDiscount = Int(DatabaseManager.shared.getSetting(key: "min_discount_threshold") ?? "0") ?? 0
        let restockOnly = DatabaseManager.shared.getSetting(key: "sale_alert_restock_only") == "1"

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

            // P0-A (a): Gate on restock window ONLY when the setting is enabled.
            if restockOnly {
                let userItem = buildUserItem(from: item)
                guard userItem.isInRestockWindow else { continue }
            }

            // P0-A (b): Gate on minimum discount threshold.
            let pctOff = historicalLow > 0
                ? (historicalLow - currentPrice) / historicalLow * 100
                : 0.0
            guard pctOff >= Double(minDiscount) else { continue }

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
    // P0-B: Respects quiet_hours_start / quiet_hours_end from user_settings.
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

        // P0-B: Determine trigger — immediate or delayed to end of quiet window.
        let trigger = quietHoursTrigger() ?? UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(identifier: notifID,
                                            content: content,
                                            trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - Quiet hours

    // Returns a UNCalendarNotificationTrigger set to fire at quiet_hours_end
    // if the current local time falls inside the quiet window.
    // Returns nil (= fire immediately) if:
    //   - either setting is missing / unparseable
    //   - current time is OUTSIDE the quiet window
    private func quietHoursTrigger() -> UNCalendarNotificationTrigger? {
        let db = DatabaseManager.shared
        guard let startStr = db.getSetting(key: "quiet_hours_start"),
              let endStr   = db.getSetting(key: "quiet_hours_end"),
              let startComponents = parseHHmm(startStr),
              let endComponents   = parseHHmm(endStr) else {
            return nil   // Missing or unparseable — safe fallback: immediate delivery.
        }

        let cal = Calendar.current
        let now = Date()
        let nowComponents = cal.dateComponents([.hour, .minute], from: now)

        let nowMinutes   = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes   = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)

        // Determine if we're inside the quiet window.
        // Handles overnight windows (e.g. 22:00 – 07:00).
        let inWindow: Bool
        if startMinutes <= endMinutes {
            // Same-day window e.g. 23:00 – 23:59 (edge case).
            inWindow = nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            // Overnight window e.g. 22:00 – 07:00.
            inWindow = nowMinutes >= startMinutes || nowMinutes < endMinutes
        }

        guard inWindow else { return nil }

        // Schedule at quiet_hours_end. If that time has already passed today, schedule tomorrow.
        var fireComponents = DateComponents()
        fireComponents.hour   = endComponents.hour
        fireComponents.minute = endComponents.minute
        fireComponents.second = 0

        // Check if end time is earlier today than now (overnight window case).
        if endMinutes < nowMinutes && startMinutes > endMinutes {
            // End time is tomorrow.
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: now) {
                var tomorrowComponents = cal.dateComponents([.year, .month, .day], from: tomorrow)
                tomorrowComponents.hour   = endComponents.hour
                tomorrowComponents.minute = endComponents.minute
                tomorrowComponents.second = 0
                return UNCalendarNotificationTrigger(dateMatching: tomorrowComponents, repeats: false)
            }
        }

        return UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
    }

    // Parses "HH:mm" string into DateComponents with .hour and .minute.
    private func parseHHmm(_ value: String) -> DateComponents? {
        let parts = value.split(separator: ":").map { Int($0) }
        guard parts.count == 2,
              let hour   = parts[0], hour   >= 0, hour   < 24,
              let minute = parts[1], minute >= 0, minute < 60 else {
            return nil
        }
        return DateComponents(hour: hour, minute: minute)
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
