// Store.swift — SmartCart/Models/Store.swift
// Represents one grocery chain. Maps to `stores` table.
// isSelected drives home-screen filter and Flipp search scope.

import Foundation

struct Store: Identifiable, Hashable {
    let id: Int64           // Primary key
    let name: String        // e.g. "No Frills"
    let flippID: String?    // Flipp's retailer identifier; nil until first sync
    let isSelected: Bool    // User chose this store in onboarding / Settings
    let lastSyncedAt: Date? // Last successful Flipp fetch; used to skip fresh stores
}
