// RestockStatus.swift — SmartCart/Models/RestockStatus.swift
// Badge state for a tracked item on the Smart List.
// Computed by ReplenishmentEngine.restockStatus(for:) and read by RestockBadge.

import Foundation

enum RestockStatus {
    case due                // Restock date has passed — red badge
    case approaching        // Within Constants.restockWindowDays — orange badge
    case ok                 // Plenty of time remaining — no badge
    case seasonalSuppressed // Seasonal item, outside its window — grey snowflake
}
