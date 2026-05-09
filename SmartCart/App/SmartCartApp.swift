// SmartCartApp.swift — SmartCart/App/SmartCartApp.swift
//
// App entry point. Registers background tasks and seeds the database
// before the first view appears.

import SwiftUI

@main
struct SmartCartApp: App {

    init() {
        // Must be called before applicationDidFinishLaunching completes.
        BackgroundSyncManager.shared.registerTasks()
        BackgroundSyncManager.shared.scheduleNextRefresh()
        // Open the database and run migrations.
        _ = DatabaseManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
