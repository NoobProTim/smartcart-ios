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

import Foundation
import BackgroundTasks

// MARK: - RefreshResult
enum RefreshResult {
    case refreshed
    case skippedNotStale(lastRefreshDate: Date)
    case noItems
}

// MARK: - BackgroundSyncManager
final class BackgroundSyncManager {

    static let shared = BackgroundSyncManager()
    private init() {}

    private let backgroundTaskID = "com.smartcart.refresh"

    // MARK: - registerBackgroundTask()
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleScheduledRefresh(task: refreshTask)
        }
    }

    // MARK: - scheduleNextRefresh()
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 23 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - handleScheduledRefresh(task:)
    private func handleScheduledRefresh(task: BGAppRefreshTask) {
        scheduleNextRefresh()
        let syncTask = Task {
            await runFullSync()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { syncTask.cancel() }
    }

    // MARK: - scheduledRefresh()
    func scheduledRefresh() async {
        await runFullSync()
    }

    // MARK: - manualRefresh()
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
