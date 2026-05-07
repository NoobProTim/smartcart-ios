// Item.swift — SmartCart/Models/Item.swift
// Canonical grocery product. Maps to `items` table.
// nameNormalised is the deduplication key — two receipt lines with the same
// normalised name resolve to the same Item row.

import Foundation

struct Item: Identifiable, Hashable {
    let id: Int64
    let nameNormalised: String
    let nameDisplay: String
    let category: String?
    let unit: String?
    let createdAt: Date
}
