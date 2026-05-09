// BackgroundSyncManager.swift — SmartCart/Engine/BackgroundSyncManager.swift
//
// Registers and handles BGAppRefreshTask for daily price + alert refresh.
// Register the task identifier in Info.plist under
// BGTaskSchedulerPermittedIdentifiers: ["com.smartcart.dailyrefresh"]
//
// Call BackgroundSyncManager.shared.registerTasks() from
// SmartCartApp.init() BEFORE the app finishes launching.

import Foundation
import BackgroundTasks

final class BackgroundSyncManager {

    static let shared = BackgroundSyncManager()
    private let taskID = "com.smartcart.dailyrefresh"
    private init() {}

    // MARK: - Registration

    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskID,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 24)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Task handler

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let work = Task {
            // 1. Fetch latest prices from Flipp for all tracked items + selected stores.
            await FlippService.shared.syncAllItems()

            // 2. Run data hygiene (delete expired flyer_sales and old alert_log rows).
            DatabaseManager.shared.runDataHygiene()

            // 3. Run the alert evaluation engine.
            AlertEngine.shared.runDailyEvaluation()

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
