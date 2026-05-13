// BackgroundSyncManager.swift
// SmartCart — Services/BackgroundSyncManager.swift
//
// Owns all background and manual price refresh logic.
// Two entry points:
//   1. handleScheduledRefresh() — called by BGAppRefreshTask (system background wake)
//   2. manualRefresh()          — called by HomeView pull-to-refresh
//
// FIX #13 (BGAppRefreshTask Minimum Interval Guard):
//   handleScheduledRefresh() previously called runFullSync() unconditionally.
//   The OS can grant BGAppRefreshTask as often as every 15 minutes on some devices,
//   which would hammer the Flipp API continuously.
//
//   Fix: at task start, read last_price_refresh from user_settings.
//   If elapsed time < Constants.minRefreshIntervalSeconds (3600s / 1 hour):
//     → skip runFullSync() entirely
//     → still call scheduleNextRefresh() so the OS keeps waking us
//     → mark task completed (success: true) so the OS doesn't penalise us
//   If elapsed time >= threshold (or no prior refresh recorded):
//     → run full sync as before
//
//   manualRefresh() has its own identical guard (added in Task #3 P1-7) and
//   is unchanged — both paths now share the same protection.
//
// TASK #3 (P1-7) context preserved:
//   manualRefresh() staleness gate uses Constants.refreshStalenessThreshold.
//   Background gate uses Constants.minRefreshIntervalSeconds.
//   Both resolve to 3600s — kept as separate named constants so each
//   path can be tuned independently in the future.

import Foundation
import BackgroundTasks

// MARK: - RefreshResult
// Returned by manualRefresh() so HomeView can show the correct subtitle.
enum RefreshResult {
    case refreshed
    case skippedNotStale(lastRefreshDate: Date)
    case noItems
}

// MARK: - BackgroundSyncManager
final class BackgroundSyncManager {

    static let shared = BackgroundSyncManager()
    private init() {}

    private let backgroundTaskID = Constants.backgroundTaskID

    // MARK: - registerBackgroundTask()
    // Registers the BGAppRefreshTask handler with the system.
    // Must be called from AppDelegate.application(_:didFinishLaunchingWithOptions:)
    // before the app finishes launching — the OS won't accept registrations after that.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleScheduledRefresh(task: refreshTask)
        }
    }

    // MARK: - scheduleNextRefresh()
    // Asks the OS to wake the app again no earlier than 23 hours from now.
    // Always called at the start of handleScheduledRefresh() — even on a skipped
    // run — so the scheduling chain never breaks.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 23 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - handleScheduledRefresh(task:)
    // Entry point for OS-granted background wakes.
    //
    // INTERVAL GUARD (Fix #13):
    //   The OS may grant BGAppRefreshTask more frequently than requested
    //   (e.g. every 15 minutes on busy devices). Without a guard, every
    //   granted wake triggers a Flipp API call — that's up to 96 calls/day
    //   per user instead of the intended 1.
    //
    //   Guard logic:
    //     1. Read last_price_refresh ISO-8601 timestamp from user_settings.
    //     2. If no timestamp exists → treat as never refreshed → run full sync.
    //     3. If elapsed < Constants.minRefreshIntervalSeconds → skip sync,
    //        complete task as success (so OS doesn't penalise), return.
    //     4. If elapsed >= threshold → run full sync.
    //
    //   scheduleNextRefresh() is always called first, before the guard,
    //   so the chain continues regardless of whether we sync or skip.
    private func handleScheduledRefresh(task: BGAppRefreshTask) {
        // Always reschedule first — ensures the chain continues even if we skip or crash
        scheduleNextRefresh()

        // Read last refresh timestamp from persistent settings
        let db = DatabaseManager.shared
        let lastRefreshString = db.getSetting(key: "last_price_refresh") ?? ""
        let lastRefreshDate   = ISO8601DateFormatter().date(from: lastRefreshString)

        // Interval guard: skip if we refreshed less than minRefreshIntervalSeconds ago
        if let lastRefresh = lastRefreshDate {
            let elapsed = Date().timeIntervalSince(lastRefresh)
            if elapsed < Constants.minRefreshIntervalSeconds {
                // Not enough time has passed — skip Flipp call entirely
                print("[BackgroundSyncManager] Skipping background sync — only \(Int(elapsed))s since last refresh (min: \(Int(Constants.minRefreshIntervalSeconds))s)")
                task.setTaskCompleted(success: true)
                return
            }
        }

        // No prior timestamp or threshold exceeded — run full sync
        let syncTask = Task {
            await runFullSync()
            task.setTaskCompleted(success: true)
        }
        // If the OS terminates the task early, cancel our async work cleanly
        task.expirationHandler = { syncTask.cancel() }
    }

    // MARK: - scheduledRefresh()
    // Public async entry point for testing or manual background simulation.
    // Not guarded — callers control whether to invoke this.
    func scheduledRefresh() async {
        await runFullSync()
    }

    // MARK: - manualRefresh()
    // Called by HomeView pull-to-refresh.
    // Has its own staleness gate using Constants.refreshStalenessThreshold.
    // Returns RefreshResult so the UI knows whether to show "Updated just now"
    // or "Already up to date".
    @discardableResult
    func manualRefresh() async -> RefreshResult {
        let db    = DatabaseManager.shared
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
    // Fetches Flipp prices for all tracked items, evaluates alerts, and
    // writes the current timestamp to last_price_refresh.
    // Called by both handleScheduledRefresh() and manualRefresh().
    // Private — external callers use scheduledRefresh() or manualRefresh().
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
