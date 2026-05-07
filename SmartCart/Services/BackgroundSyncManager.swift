// BackgroundSyncManager.swift — SmartCart/Services/BackgroundSyncManager.swift
// Manages daily background price sync via BGAppRefreshTask.
// Also handles manual pull-to-refresh with a 1-hour cooldown.

import Foundation
import BackgroundTasks

final class BackgroundSyncManager {
    static let shared = BackgroundSyncManager()
    private init() {}

    private let taskID = "com.smartcart.priceSync"

    /// Register the background task identifier. Call from SmartCartApp init.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            self.handleBackgroundSync(task: task as! BGAppRefreshTask)
        }
    }

    /// Schedule the next background sync ~24h from now.
    func scheduleNextSync() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 24)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called by the OS when a background slot is granted.
    private func handleBackgroundSync(task: BGAppRefreshTask) {
        scheduleNextSync()
        let syncTask = Task {
            await runFullSync()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Called from pull-to-refresh — only runs if last sync was > 1 hour ago.
    func manualRefresh() async {
        let db = DatabaseManager.shared
        if let lastStr = db.getSetting(key: "last_price_refresh"),
           let lastDate = ISO8601DateFormatter().date(from: lastStr) {
            let hoursSince = Date().timeIntervalSince(lastDate) / 3600
            guard hoursSince > Double(Constants.manualRefreshCooldownHours) else {
                print("[BackgroundSyncManager] Skipping refresh — last sync was \(String(format: "%.1f", hoursSince))h ago")
                return
            }
        }
        await runFullSync()
    }

    /// Runs the full sync pipeline: fetch prices → evaluate alerts.
    private func runFullSync() async {
        let userItems = DatabaseManager.shared.fetchUserItems()
        await FlippService.shared.fetchPrices(for: userItems)
        await AlertEngine.shared.evaluate()
        DatabaseManager.shared.setSetting(
            key: "last_price_refresh",
            value: ISO8601DateFormatter().string(from: Date())
        )
    }
}
