// Store.swift — SmartCart/Models/Store.swift

import Foundation

struct Store: Identifiable, Equatable {
    let id: Int64
    let name: String
    let flippID: String?
    var isSelected: Bool
    var lastSyncedAt: Date?
}
