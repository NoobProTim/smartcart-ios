// BackgroundSyncManager.swift — SmartCart/Services/BackgroundSyncManager.swift
//
// Coordinates the daily price fetch + alert evaluation cycle.
// Registered as a BGAppRefreshTask in SmartCartApp so iOS can wake the app once per day.
//
// Responsibilities:
//   1. Read user postal code from DatabaseManager.
//   2. Collect all user item names for Flipp lookup.
//   3. Call FlippService.fetchPrices().
//   4. Call AlertEngine.evaluateAlerts().
//   5. Write "last_price_refresh" to user_settings.
//   6. Reschedule the next BGAppRefreshTask.
//
// manualRefresh() is exposed to pull-to-refresh in HomeView.
// It respects a 1-hour cooldown — HomeView checks this before calling.

import Foundation
import BackgroundTasks

final class BackgroundSyncManager {

    static let shared = BackgroundSyncManager()
    private init() {}

    // Task identifier — must match the entry in Info.plist BGTaskSchedulerPermittedIdentifiers.
    static let taskID = "com.smartcart.app.pricerefresh"

    // MARK: - Registration (call in SmartCartApp.init)

    // Registers the background task handler with iOS.
    // Must be called before the app finishes launching.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            self.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }

    // MARK: - Background task handler

    // Called by iOS when the background refresh fires.
    // Sets an expiry handler in case iOS terminates early.
    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()
        let op = Task {
            await runSync()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            op.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // Schedules the next background refresh ~24 hours from now.
    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 23)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Manual refresh (pull-to-refresh)

    // Exposed to HomeView. HomeView must check isRefreshStale() before calling.
    func manualRefresh() async {
        await runSync()
    }

    // Returns true when last_price_refresh is more than 1 hour ago (or has never run).
    // HomeView uses this to decide whether pull-to-refresh should actually fetch.
    func isRefreshStale() -> Bool {
        guard let lastStr = DatabaseManager.shared.getSetting(key: "last_price_refresh"),
              let lastDate = DateHelper.date(from: lastStr) else { return true }
        return Date().timeIntervalSince(lastDate) > 3600
    }

    // MARK: - Core sync

    // Full sync cycle: fetch prices → evaluate alerts → record timestamp.
    private func runSync() async {
        let postalCode = DatabaseManager.shared.getSetting(key: "user_postal_code") ?? ""
        guard !postalCode.isEmpty else {
            print("[BackgroundSyncManager] No postal code set — skipping sync.")
            return
        }

        // Build name → itemID map from the user’s tracked list.
        let items = DatabaseManager.shared.fetchUserItems()
        var nameMap: [String: Int64] = [:]
        for item in items {
            nameMap[item.nameDisplay] = item.itemID
        }

        do {
            try await FlippService.shared.fetchPrices(for: nameMap, postalCode: postalCode)
        } catch FlippFetchError.serviceUnavailable {
            print("[BackgroundSyncManager] Flipp unavailable — skipping alert evaluation.")
            return
        } catch {
            print("[BackgroundSyncManager] Fetch error: \(error)")
            return
        }

        await AlertEngine.shared.evaluateAlerts()
        DatabaseManager.shared.setSetting(key: "last_price_refresh",
                                          value: DateHelper.nowString())
    }
}
