// BackgroundSyncManager.swift
// SmartCart — Services/BackgroundSyncManager.swift
//
// Owns all background and manual price refresh logic.
// Two entry points:
//   1. scheduledRefresh() — called by BGAppRefreshTask (system background wake)
//   2. manualRefresh()    — called by HomeView pull-to-refresh
//
// UPDATED IN TASK #3 (P1-7):
// manualRefresh() was a stub in Task #2 — it refreshed local data but never
// called FlippService or AlertEngine. Fully implemented here with:
//   - Staleness gate: only fires network calls if last_price_refresh > 1 hour ago
//   - Returns a RefreshResult enum so HomeView can show the correct subtitle
//   - Calls AlertEngine.evaluate() after the Flipp sync completes
//
// WHY THE STALENESS GATE:
// Without it, rapid pull-to-refresh triggers 30+ serial Flipp API calls.
// The gate also prevents burning through any undocumented rate limits on the
// Flipp endpoint. 1 hour matches Constants.refreshStalenessThreshold.

import Foundation
import BackgroundTasks

// MARK: - RefreshResult
// Returned by manualRefresh() so HomeView can show an informative subtitle
// without HomeView needing to know anything about last_price_refresh timestamps.
enum RefreshResult {
    case refreshed
    case skippedNotStale(lastRefreshDate: Date)
    case noItems
}

// MARK: - BackgroundSyncManager
final class BackgroundSyncManager {

    static let shared = BackgroundSyncManager()
    private init() {}

    // BGTaskScheduler identifier — must match Info.plist BGTaskSchedulerPermittedIdentifiers
    private let backgroundTaskID = "com.smartcart.refresh"

    // MARK: - registerBackgroundTask()
    // Registers the BGAppRefreshTask handler with the system.
    // Must be called from SmartCartApp.init() — before the app finishes launching.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleScheduledRefresh(task: refreshTask)
        }
    }

    // MARK: - scheduleNextRefresh()
    // Asks the system to wake the app once per day for a background sync.
    // Call this at the end of every refresh so the next wake is always queued.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 23 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - handleScheduledRefresh(task:)
    // Called by the system when a BGAppRefreshTask fires.
    // Sets the task's expiration handler so the system can interrupt gracefully.
    private func handleScheduledRefresh(task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let syncTask = Task {
            await runFullSync()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }

    // MARK: - scheduledRefresh()
    // Public wrapper for use in previews and testing.
    func scheduledRefresh() async {
        await runFullSync()
    }

    // MARK: - manualRefresh()
    // Called by HomeView's pull-to-refresh gesture.
    // Applies a staleness gate: if the last successful sync was < 1 hour ago,
    // skip the network calls and return .skippedNotStale.
    //
    // Returns a RefreshResult that HomeView uses to build its subtitle text.
    @discardableResult
    func manualRefresh() async -> RefreshResult {
        let db = DatabaseManager.shared

        let items = db.fetchUserItems()
        guard !items.isEmpty else { return .noItems }

        let lastRefreshString = db.getSetting(key: "last_price_refresh") ?? ""
        if let lastRefreshDate = ISO8601DateFormatter().date(from: lastRefreshString) {
            let elapsed = Date().timeIntervalSince(lastRefreshDate)
            if elapsed < Constants.refreshStalenessThreshold {
                return .skippedNotStale(lastRefreshDate: lastRefreshDate)
            }
        }

        await runFullSync()
        return .refreshed
    }

    // MARK: - runFullSync()
    // The core sync pipeline:
    //   1. Fetch prices from Flipp for all tracked items
    //   2. Evaluate alerts based on new price data
    //   3. Update last_price_refresh timestamp
    private func runFullSync() async {
        let items = DatabaseManager.shared.fetchUserItems()
        guard !items.isEmpty else { return }

        await FlippService.shared.fetchPrices(for: items)
        AlertEngine.shared.evaluate()

        let timestamp = ISO8601DateFormatter().string(from: Date())
        DatabaseManager.shared.setSetting(key: "last_price_refresh", value: timestamp)

        print("[BackgroundSyncManager] Full sync complete at \(timestamp)")
    }
}
