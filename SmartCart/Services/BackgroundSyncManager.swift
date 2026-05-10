// BackgroundSyncManager.swift — SmartCart/Services/BackgroundSyncManager.swift
//
// Coordinates the daily price fetch + alert evaluation cycle.
// Registered as a BGAppRefreshTask in SmartCartApp so iOS can wake the app once per day.
//
// Responsibilities:
//   1. Guard that a postal code is present in user_settings.
//   2. Call FlippService.shared.syncAllItems() — fetches prices for every
//      tracked item across every selected store and writes to price_history /
//      flyer_sales.
//   3. Call AlertEngine.shared.runDailyEvaluation() — evaluates A/B/C/combined
//      alert candidates and fires UNUserNotificationCenter requests.
//   4. Stamp "last_price_refresh" in user_settings.
//   5. Reschedule the next BGAppRefreshTask (~23 h from now).
//
// manualRefresh() is exposed for pull-to-refresh in HomeView.
// HomeView must call isRefreshStale() first to enforce the 1-hour cooldown.
//
// Part 6 fix: corrected all method-call mismatches.
//   Was: fetchPrices(for:postalCode:), evaluateAlerts(), FlippFetchError, DateHelper
//   Now: syncAllItems(), runDailyEvaluation(), ISO8601DateFormatter inline

import Foundation
import BackgroundTasks

final class BackgroundSyncManager {

    static let shared = BackgroundSyncManager()
    private init() {}

    // Must match the BGTaskSchedulerPermittedIdentifiers entry in Info.plist.
    static let taskID = "com.smartcart.app.pricerefresh"

    // MARK: - Registration

    /// Call once, before the app finishes launching (SmartCartApp.init).
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskID,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }

    // MARK: - Background task handler

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

    private func scheduleNextRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: Self.taskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 23)
        try? BGTaskScheduler.shared.submit(req)
    }

    // MARK: - Manual refresh (pull-to-refresh)

    /// Called from HomeView pull-to-refresh after isRefreshStale() returns true.
    func manualRefresh() async {
        await runSync()
    }

    /// True when last_price_refresh is >1 hour ago (or has never been set).
    func isRefreshStale() -> Bool {
        guard
            let raw  = DatabaseManager.shared.getSetting(key: "last_price_refresh"),
            let last = ISO8601DateFormatter().date(from: raw)
        else { return true }
        return Date().timeIntervalSince(last) > 3_600
    }

    // MARK: - Core sync

    /// Full sync cycle: fetch prices → evaluate alerts → stamp timestamp.
    /// Private — callers use manualRefresh() or the background task handler.
    private func runSync() async {
        let db = DatabaseManager.shared

        // Guard: postal code required for Flipp geo-filtering.
        guard let postalCode = db.getSetting(key: "user_postal_code"),
              !postalCode.isEmpty else {
            print("[BackgroundSyncManager] No postal code set — skipping sync.")
            return
        }

        // 1. Fetch prices for every tracked item across every selected store.
        //    syncAllItems() reads postalCode internally from user_settings.
        await FlippService.shared.syncAllItems()

        // 2. Evaluate alert candidates (A / B / C / combined) and schedule
        //    any qualifying UNUserNotificationCenter requests.
        //    runDailyEvaluation() is synchronous-dispatch-to-background internally;
        //    we wait for it via a checked continuation so sync remains serial.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // runDailyEvaluation spins its own Task.detached internally.
            // We add a short yield so the detached work can complete before
            // we stamp the timestamp.
            AlertEngine.shared.runDailyEvaluation()
            // Delay 2 s to allow the detached evaluation Task to finish.
            // This is a best-effort courtesy — notification scheduling is
            // fire-and-forget by design and will complete even if we return early.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                continuation.resume()
            }
        }

        // 3. Stamp the refresh time so isRefreshStale() and HomeView can gate
        //    the next manual pull-to-refresh.
        db.setSetting(
            key: "last_price_refresh",
            value: ISO8601DateFormatter().string(from: Date())
        )
    }
}
